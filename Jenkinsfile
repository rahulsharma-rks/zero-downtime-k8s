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
    }

    stages {

        stage('Test Application') {
            steps {
                sh '''
                    set -e

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

                    echo "Building Docker image:"
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

                    echo "Logging in to Amazon ECR..."

                    aws ecr get-login-password \
                        --region "${AWS_REGION}" |
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

                    echo "Pushing image:"
                    echo "${IMAGE_NAME}"

                    docker push "${IMAGE_NAME}"
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                sh '''
                    set -e

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

                    echo "Waiting for Kubernetes rollout..."

                    kubectl rollout status \
                        deployment/${K8S_DEPLOYMENT} \
                        --namespace "${K8S_NAMESPACE}" \
                        --timeout=5m
                '''
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Deployment Status"
                    echo "========================================"

                    kubectl get deployment "${K8S_DEPLOYMENT}" \
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

                    kubectl get deployment "${K8S_DEPLOYMENT}" \
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

                    echo "Testing /health..."

                    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                        "${ALB_URL}/health")

                    echo "Health endpoint HTTP status: ${HTTP_CODE}"

                    if [ "${HTTP_CODE}" != "200" ]; then
                        echo "ALB health check failed"
                        exit 1
                    fi

                    echo ""
                    echo "Testing application endpoint..."

                    RESPONSE=$(curl -fsS "${ALB_URL}/")

                    echo "${RESPONSE}"

                    echo ""
                    echo "Checking deployed application version..."

                    echo "${RESPONSE}" | grep -q "Application Version: ${IMAGE_TAG}"

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
        }

        always {
            sh '''
                docker logout "${ECR_REGISTRY}" || true
            '''
        }
    }
}
