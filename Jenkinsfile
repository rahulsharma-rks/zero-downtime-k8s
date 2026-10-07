pipeline {
    agent any

    environment {
        AWS_REGION     = 'ap-south-1'
        AWS_ACCOUNT_ID = '520701146276'

        ECR_REPOSITORY = 'zero-downtime-app'
        ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_TAG      = "${BUILD_NUMBER}"
        IMAGE_NAME     = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

        EKS_CLUSTER    = 'zero-downtime-eks'
        K8S_NAMESPACE  = 'zero-downtime'
        K8S_DEPLOYMENT = 'zero-downtime-app'
        K8S_CONTAINER  = 'app'

        ALB_URL        = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'

        DEPLOYMENT_STARTED = 'false'
    }

    stages {

        stage('Test Application') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Testing Application"
                    echo "========================================"

                    echo "Creating Python virtual environment..."
                    rm -rf .venv
                    python3 -m venv .venv

                    echo "Installing application dependencies..."
                    .venv/bin/python -m pip install --upgrade pip
                    .venv/bin/pip install -r app/requirements.txt

                    echo "Running Python syntax check..."
                    .venv/bin/python -m py_compile app/app.py

                    echo "Running application tests..."
                    .venv/bin/python - <<'PY'
from app.app import app

client = app.test_client()

response = client.get("/")
assert response.status_code == 200, f"/ returned {response.status_code}"

response = client.get("/health")
assert response.status_code == 200, f"/health returned {response.status_code}"

response = client.get("/ready")
assert response.status_code == 200, f"/ready returned {response.status_code}"

print("Application tests passed")
PY
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Building Docker Image"
                    echo "========================================"

                    echo "Building image:"
                    echo "${IMAGE_NAME}"

                    docker build \
                        --build-arg APP_VERSION="${IMAGE_TAG}" \
                        -t "${IMAGE_NAME}" \
                        ./app
                '''
            }
        }

        stage('Login to ECR') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Logging in to Amazon ECR"
                    echo "========================================"

                    aws ecr get-login-password \
                        --region "${AWS_REGION}" \
                        | docker login \
                        --username AWS \
                        --password-stdin "${ECR_REGISTRY}"
                '''
            }
        }

        stage('Push Image') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Pushing Docker Image"
                    echo "========================================"

                    echo "Pushing image:"
                    echo "${IMAGE_NAME}"

                    docker push "${IMAGE_NAME}"
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                script {
                    sh '''
                        set -e

                        echo "========================================"
                        echo "Deploying to EKS"
                        echo "========================================"

                        echo "Updating kubeconfig..."

                        aws eks update-kubeconfig \
                            --region "${AWS_REGION}" \
                            --name "${EKS_CLUSTER}"

                        echo "Deploying image:"
                        echo "${IMAGE_NAME}"

                        kubectl set image \
                            deployment/${K8S_DEPLOYMENT} \
                            ${K8S_CONTAINER}="${IMAGE_NAME}" \
                            --namespace "${K8S_NAMESPACE}"
                    '''

                    env.DEPLOYMENT_STARTED = 'true'

                    sh '''
                        set -e

                        echo "Waiting for Kubernetes rollout..."

                        kubectl rollout status \
                            deployment/${K8S_DEPLOYMENT} \
                            --namespace "${K8S_NAMESPACE}" \
                            --timeout=5m
                    '''
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Deployment Status"
                    echo "========================================"

                    kubectl get deployment \
                        "${K8S_DEPLOYMENT}" \
                        --namespace "${K8S_NAMESPACE}"

                    echo ""
                    echo "========================================"
                    echo "Pod Status"
                    echo "========================================"

                    kubectl get pods \
                        --namespace "${K8S_NAMESPACE}" \
                        -o wide

                    echo ""
                    echo "========================================"
                    echo "Deployed Image"
                    echo "========================================"

                    kubectl get deployment \
                        "${K8S_DEPLOYMENT}" \
                        --namespace "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}'

                    echo ""
                '''
            }
        }

        stage('ALB Smoke Test') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "ALB Smoke Test"
                    echo "========================================"

                    MAX_ATTEMPTS=6
                    SLEEP_SECONDS=5

                    echo "Testing ALB health endpoint..."

                    HEALTH_SUCCESS=false

                    for ATTEMPT in $(seq 1 ${MAX_ATTEMPTS}); do

                        echo "Health check attempt ${ATTEMPT}/${MAX_ATTEMPTS}"

                        HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                            --max-time 10 \
                            "${ALB_URL}/health" || true)

                        echo "Health endpoint HTTP status: ${HTTP_CODE}"

                        if [ "${HTTP_CODE}" = "200" ]; then
                            HEALTH_SUCCESS=true
                            break
                        fi

                        if [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; then
                            echo "Health check failed. Waiting ${SLEEP_SECONDS} seconds..."
                            sleep "${SLEEP_SECONDS}"
                        fi
                    done

                    if [ "${HEALTH_SUCCESS}" != "true" ]; then
                        echo "ALB health check failed after ${MAX_ATTEMPTS} attempts."
                        exit 1
                    fi

                    echo ""
                    echo "Testing application endpoint..."

                    RESPONSE=""

                    for ATTEMPT in $(seq 1 ${MAX_ATTEMPTS}); do

                        echo "Application check attempt ${ATTEMPT}/${MAX_ATTEMPTS}"

                        RESPONSE=$(curl -fsS \
                            --max-time 10 \
                            "${ALB_URL}/" || true)

                        if echo "${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                            echo "Application version ${IMAGE_TAG} verified."
                            break
                        fi

                        if [ "${ATTEMPT}" -lt "${MAX_ATTEMPTS}" ]; then
                            echo "Expected application version not detected."
                            echo "Waiting ${SLEEP_SECONDS} seconds..."
                            sleep "${SLEEP_SECONDS}"
                        fi
                    done

                    echo ""
                    echo "ALB response:"
                    echo "${RESPONSE}"

                    echo ""
                    echo "Final version validation..."

                    echo "${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"

                    echo "Application version ${IMAGE_TAG} verified."

                    echo ""
                    echo "ALB smoke test passed."
                '''
            }
        }
    }

    post {

        success {
            echo "========================================"
            echo "CI/CD PIPELINE SUCCESSFUL"
            echo "========================================"

            echo "Deployed image: ${IMAGE_NAME}"
        }

        failure {
            echo "========================================"
            echo "CI/CD PIPELINE FAILED"
            echo "========================================"

            script {
                if (env.DEPLOYMENT_STARTED == 'true') {

                    echo "A Kubernetes deployment was started."
                    echo "Initiating automatic rollback..."

                    sh '''
                        set +e

                        echo "========================================"
                        echo "AUTOMATIC ROLLBACK"
                        echo "========================================"

                        echo "Current deployment image:"
                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            --namespace "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}'

                        echo ""

                        echo "Rolling back deployment..."

                        kubectl rollout undo \
                            deployment/${K8S_DEPLOYMENT} \
                            --namespace "${K8S_NAMESPACE}"

                        echo ""
                        echo "Waiting for rollback to complete..."

                        kubectl rollout status \
                            deployment/${K8S_DEPLOYMENT} \
                            --namespace "${K8S_NAMESPACE}" \
                            --timeout=5m

                        echo ""
                        echo "Deployment image after rollback:"

                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            --namespace "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}'

                        echo ""

                        echo "Automatic rollback completed."
                    '''

                } else {

                    echo "No Kubernetes deployment was started."
                    echo "Rollback is not required."
                }
            }
        }

        always {
            sh '''
                docker logout "${ECR_REGISTRY}" || true
            '''
        }
    }
}
