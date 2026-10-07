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

        ROLLBACK_PERFORMED = 'false'
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

                    /*
                     * Capture the exact image currently running.
                     */

                    sh '''
                        set -e

                        echo "========================================"
                        echo "Preparing EKS Deployment"
                        echo "========================================"

                        echo "Updating kubeconfig..."

                        aws eks update-kubeconfig \
                            --region "${AWS_REGION}" \
                            --name "${EKS_CLUSTER}"

                        echo ""
                        echo "Getting currently deployed image..."

                        CURRENT_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                            --namespace "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}')

                        if [ -z "${CURRENT_IMAGE}" ]; then
                            echo "ERROR: Could not determine current deployment image."
                            exit 1
                        fi

                        echo "Current image:"
                        echo "${CURRENT_IMAGE}"

                        echo "${CURRENT_IMAGE}" > .previous_image

                        echo ""
                        echo "Previous image saved successfully."
                    '''

                    /*
                     * Deploy the new image.
                     */

                    sh '''
                        set -e

                        echo "========================================"
                        echo "Deploying New Image"
                        echo "========================================"

                        echo "New image:"
                        echo "${IMAGE_NAME}"

                        kubectl set image \
                            deployment/${K8S_DEPLOYMENT} \
                            ${K8S_CONTAINER}="${IMAGE_NAME}" \
                            --namespace "${K8S_NAMESPACE}"

                        echo ""
                        echo "Kubernetes deployment update accepted."
                    '''

                    /*
                     * Wait for rollout without immediately aborting.
                     */

                    def rolloutStatus = sh(
                        script: '''
                            set -e

                            echo "========================================"
                            echo "Waiting for Kubernetes Rollout"
                            echo "========================================"

                            kubectl rollout status \
                                deployment/${K8S_DEPLOYMENT} \
                                --namespace "${K8S_NAMESPACE}" \
                                --timeout=5m
                        ''',
                        returnStatus: true
                    )

                    /*
                     * Normal successful deployment.
                     */

                    if (rolloutStatus == 0) {

                        echo "========================================"
                        echo "KUBERNETES ROLLOUT SUCCESSFUL"
                        echo "========================================"

                        echo "New image successfully deployed:"
                        echo "${IMAGE_NAME}"

                    } else {

                        /*
                         * Deployment failed.
                         */

                        echo "========================================"
                        echo "DEPLOYMENT FAILED"
                        echo "========================================"

                        echo "The new image failed the Kubernetes rollout."
                        echo "Automatic rollback will now be performed."

                        def previousImage = sh(
                            script: 'cat .previous_image',
                            returnStdout: true
                        ).trim()

                        echo ""
                        echo "Previous image:"
                        echo "${previousImage}"

                        echo ""
                        echo "Failed image:"
                        echo "${IMAGE_NAME}"

                        if (previousImage == env.IMAGE_NAME) {
                            error(
                                "Previous image is identical to failed image. " +
                                "Automatic rollback cannot continue."
                            )
                        }

                        /*
                         * Restore the exact previous image.
                         */

                        echo "========================================"
                        echo "RESTORING PREVIOUS IMAGE"
                        echo "========================================"

                        sh """
                            set -e

                            echo "Restoring image:"
                            echo "${previousImage}"

                            kubectl set image \
                                deployment/${K8S_DEPLOYMENT} \
                                ${K8S_CONTAINER}="${previousImage}" \
                                --namespace "${K8S_NAMESPACE}"

                            echo ""
                            echo "Previous image restored in Deployment."
                        """

                        /*
                         * Wait for rollback rollout.
                         */

                        echo "========================================"
                        echo "WAITING FOR ROLLBACK ROLLOUT"
                        echo "========================================"

                        def rollbackStatus = sh(
                            script: '''
                                set -e

                                kubectl rollout status \
                                    deployment/${K8S_DEPLOYMENT} \
                                    --namespace "${K8S_NAMESPACE}" \
                                    --timeout=5m
                            ''',
                            returnStatus: true
                        )

                        if (rollbackStatus != 0) {
                            error(
                                "Automatic rollback failed. " +
                                "The previous image did not successfully roll out."
                            )
                        }

                        echo "Rollback rollout completed successfully."

                        /*
                         * Verify exact image restoration.
                         */

                        echo "========================================"
                        echo "VERIFYING RESTORED IMAGE"
                        echo "========================================"

                        def restoredImage = sh(
                            script: '''
                                kubectl get deployment "${K8S_DEPLOYMENT}" \
                                    --namespace "${K8S_NAMESPACE}" \
                                    -o jsonpath='{.spec.template.spec.containers[0].image}'
                            ''',
                            returnStdout: true
                        ).trim()

                        echo "Expected image:"
                        echo "${previousImage}"

                        echo "Restored image:"
                        echo "${restoredImage}"

                        if (restoredImage != previousImage) {
                            error(
                                "Rollback verification failed. " +
                                "Expected ${previousImage}, " +
                                "but found ${restoredImage}."
                            )
                        }

                        echo "Rollback image verification passed."

                        /*
                         * Verify ALB recovery.
                         */

                        echo "========================================"
                        echo "VERIFYING ALB AFTER ROLLBACK"
                        echo "========================================"

                        sh '''
                            set -e

                            MAX_ATTEMPTS=12
                            SLEEP_SECONDS=5

                            ALB_HEALTH_PASSED=false

                            echo "Checking ALB health endpoint..."

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
                                    echo "ALB health check passed."
                                    ALB_HEALTH_PASSED=true
                                    break
                                fi

                                if [ "${i}" -eq "${MAX_ATTEMPTS}" ]; then
                                    echo "ALB health check failed after rollback."
                                    exit 1
                                fi

                                sleep "${SLEEP_SECONDS}"
                            done

                            if [ "${ALB_HEALTH_PASSED}" != "true" ]; then
                                echo "ALB health verification failed."
                                exit 1
                            fi

                            echo ""
                            echo "Checking application response..."

                            RESPONSE=$(curl \
                                --silent \
                                --max-time 10 \
                                "${ALB_URL}/")

                            echo "${RESPONSE}"

                            if ! echo "${RESPONSE}" | \
                                grep -q "Zero Downtime Kubernetes Demo"; then

                                echo "Application response verification failed."
                                exit 1
                            fi

                            echo "Application response is healthy."

                            echo ""
                            echo "Checking that failed version is no longer served..."

                            if echo "${RESPONSE}" | \
                                grep -q "<strong>${IMAGE_TAG}</strong>"; then

                                echo "Failed image ${IMAGE_TAG} is still being served."
                                exit 1
                            fi

                            echo "Failed version is no longer being served."

                            echo ""
                            echo "========================================"
                            echo "AUTOMATIC ROLLBACK VERIFIED"
                            echo "========================================"
                            echo "Failed image:   ${IMAGE_NAME}"
                            echo "Restored image: ${previousImage}"
                            echo "ALB health:     HTTP 200"
                            echo "Application:    Healthy"
                            echo "Failed version: No longer served"
                            echo "========================================"
                        '''

                        env.ROLLBACK_PERFORMED = 'true'

                        echo "========================================"
                        echo "DEPLOYMENT FAILURE RECOVERED"
                        echo "========================================"
                        echo "Automatic rollback completed successfully."
                        echo "The pipeline will continue."
                    }
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
                        -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
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

                    if [ "${ROLLBACK_PERFORMED}" = "true" ]; then

                        echo "Automatic rollback was performed successfully."
                        echo "ALB was already verified during rollback."
                        echo "Skipping normal deployment version check."

                        exit 0
                    fi

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

                        if echo "${RESPONSE}" | \
                            grep -q "<strong>${IMAGE_TAG}</strong>"; then

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
            script {
                echo "========================================"
                echo "CI/CD PIPELINE SUCCESSFUL"
                echo "========================================"

                if (env.ROLLBACK_PERFORMED == 'true') {
                    echo "Deployment failed but was automatically rolled back."
                    echo "Previous application version has been restored."
                    echo "ALB recovery verification passed."
                    echo "Pipeline completed successfully after rollback."
                } else {
                    echo "Application image: ${IMAGE_NAME}"
                    echo "Deployment completed successfully."
                }
            }
        }

        failure {
            script {
                echo "========================================"
                echo "CI/CD PIPELINE FAILED"
                echo "========================================"

                if (env.ROLLBACK_PERFORMED == 'true') {
                    echo "Rollback was attempted but the pipeline still failed."
                    echo "Manual investigation is required."
                } else {
                    echo "Pipeline failed before successful deployment recovery."
                }
            }
        }

        always {
            sh '''
                docker logout "${ECR_REGISTRY}" || true
                rm -f .previous_image
            '''
        }
    }
}
