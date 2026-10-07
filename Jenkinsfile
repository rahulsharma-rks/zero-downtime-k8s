pipeline {
    agent any

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT_ID = '520701146276'

        ECR_REPOSITORY = 'zero-downtime-app'
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

        IMAGE_TAG = "${BUILD_NUMBER}"
        IMAGE_NAME = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

        EKS_CLUSTER = 'zero-downtime-eks'
        K8S_NAMESPACE = 'zero-downtime'
        K8S_DEPLOYMENT = 'zero-downtime-app'
        K8S_CONTAINER = 'app'

        ALB_URL = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'

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
                        --region "${AWS_REGION}" | \
                        docker login \
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

                        echo "Kubernetes deployment update accepted."
                    '''

                    /*
                     * IMPORTANT:
                     * Set this immediately after kubectl set image succeeds.
                     *
                     * If rollout status fails or times out, Jenkins still knows
                     * that a deployment was already started and must be rolled back.
                     */
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
                    echo "Verifying Kubernetes Deployment"
                    echo "========================================"

                    echo "Deployment:"
                    kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}"

                    echo ""
                    echo "Pods:"
                    kubectl get pods \
                        -n "${K8S_NAMESPACE}" \
                        -o wide

                    echo ""
                    echo "Deployed image:"
                    kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}{"\\n"}'
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

                    for i in $(seq 1 ${MAX_ATTEMPTS}); do
                        echo "Health check attempt ${i}/${MAX_ATTEMPTS}"

                        HTTP_STATUS=$(curl \
                            --silent \
                            --output /dev/null \
                            --write-out "%{http_code}" \
                            --max-time 10 \
                            "${ALB_URL}/health" || true)

                        echo "HTTP status: ${HTTP_STATUS}"

                        if [ "${HTTP_STATUS}" = "200" ]; then
                            echo "ALB health check passed."
                            break
                        fi

                        if [ "${i}" -eq "${MAX_ATTEMPTS}" ]; then
                            echo "ALB health check failed."
                            exit 1
                        fi

                        sleep "${SLEEP_SECONDS}"
                    done

                    echo ""
                    echo "Testing application endpoint..."

                    for i in $(seq 1 ${MAX_ATTEMPTS}); do
                        echo "Application check attempt ${i}/${MAX_ATTEMPTS}"

                        RESPONSE=$(curl \
                            --silent \
                            --max-time 10 \
                            "${ALB_URL}/" || true)

                        echo "${RESPONSE}"

                        if echo "${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                            echo "Application version ${IMAGE_TAG} is being served."
                            break
                        fi

                        if [ "${i}" -eq "${MAX_ATTEMPTS}" ]; then
                            echo "Application version verification failed."
                            exit 1
                        fi

                        sleep "${SLEEP_SECONDS}"
                    done

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
            echo "Application image: ${IMAGE_NAME}"
            echo "Deployment completed successfully."
        }

        failure {
            echo "========================================"
            echo "CI/CD PIPELINE FAILED"
            echo "========================================"

            script {

                if (env.DEPLOYMENT_STARTED == 'true') {

                    echo "A Kubernetes deployment was started."
                    echo "Automatic rollback will now be attempted."

                    /*
                     * Do not allow rollback commands to hide the original
                     * deployment failure.
                     */
                    sh '''
                        set +e

                        echo "========================================"
                        echo "Starting Automatic Rollback"
                        echo "========================================"

                        echo "Current deployment image:"
                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}{"\\n"}'

                        echo ""
                        echo "Rolling back deployment..."

                        kubectl rollout undo \
                            deployment/${K8S_DEPLOYMENT} \
                            --namespace "${K8S_NAMESPACE}"

                        if [ $? -ne 0 ]; then
                            echo "ERROR: kubectl rollout undo failed."
                            exit 1
                        fi

                        echo ""
                        echo "Waiting for rollback to complete..."

                        kubectl rollout status \
                            deployment/${K8S_DEPLOYMENT} \
                            --namespace "${K8S_NAMESPACE}" \
                            --timeout=5m

                        if [ $? -ne 0 ]; then
                            echo "ERROR: Kubernetes rollback did not complete successfully."
                            exit 1
                        fi

                        echo ""
                        echo "Rollback completed successfully."

                        echo ""
                        echo "Restored deployment image:"

                        RESTORED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}')

                        echo "${RESTORED_IMAGE}"

                        if [ -z "${RESTORED_IMAGE}" ]; then
                            echo "ERROR: Could not determine restored image."
                            exit 1
                        fi

                        if [ "${RESTORED_IMAGE}" = "${IMAGE_NAME}" ]; then
                            echo "ERROR: Deployment still references failed image ${IMAGE_NAME}."
                            exit 1
                        fi

                        echo ""
                        echo "Rollback image verification passed."

                        echo ""
                        echo "========================================"
                        echo "Verifying ALB After Rollback"
                        echo "========================================"

                        MAX_ATTEMPTS=12
                        SLEEP_SECONDS=5

                        echo "Waiting for ALB health after rollback..."

                        ALB_HEALTH_PASSED=false

                        for i in $(seq 1 ${MAX_ATTEMPTS}); do

                            echo "ALB health attempt ${i}/${MAX_ATTEMPTS}"

                            HTTP_STATUS=$(curl \
                                --silent \
                                --output /dev/null \
                                --write-out "%{http_code}" \
                                --max-time 10 \
                                "${ALB_URL}/health" || true)

                            echo "HTTP status: ${HTTP_STATUS}"

                            if [ "${HTTP_STATUS}" = "200" ]; then
                                ALB_HEALTH_PASSED=true
                                echo "ALB health check passed."
                                break
                            fi

                            sleep "${SLEEP_SECONDS}"
                        done

                        if [ "${ALB_HEALTH_PASSED}" != "true" ]; then
                            echo "ERROR: ALB health check failed after rollback."
                            exit 1
                        fi

                        echo ""
                        echo "Checking application response after rollback..."

                        ALB_RESPONSE=""

                        for i in $(seq 1 ${MAX_ATTEMPTS}); do

                            echo "Application verification attempt ${i}/${MAX_ATTEMPTS}"

                            ALB_RESPONSE=$(curl \
                                --silent \
                                --max-time 10 \
                                "${ALB_URL}/" || true)

                            echo "${ALB_RESPONSE}"

                            if [ -n "${ALB_RESPONSE}" ] && \
                               echo "${ALB_RESPONSE}" | grep -q "Zero Downtime Kubernetes Demo"; then
                                echo "Application response is healthy."
                                break
                            fi

                            sleep "${SLEEP_SECONDS}"
                        done

                        if ! echo "${ALB_RESPONSE}" | grep -q "Zero Downtime Kubernetes Demo"; then
                            echo "ERROR: Application verification failed after rollback."
                            exit 1
                        fi

                        echo ""
                        echo "Ensuring failed image is no longer being served..."

                        if echo "${ALB_RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                            echo "ERROR: Failed image version ${IMAGE_TAG} is still being served by ALB."
                            exit 1
                        fi

                        echo ""
                        echo "========================================"
                        echo "AUTOMATIC ROLLBACK VERIFIED"
                        echo "========================================"
                        echo "Failed image:    ${IMAGE_NAME}"
                        echo "Restored image:  ${RESTORED_IMAGE}"
                        echo "ALB health:      HTTP 200"
                        echo "ALB application: Healthy"
                        echo "Failed version:  No longer served"
                    '''

                    if (sh(script: 'true', returnStatus: true) != 0) {
                        error('Automatic rollback verification failed.')
                    }

                    echo "Automatic rollback and ALB recovery verification completed."

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
