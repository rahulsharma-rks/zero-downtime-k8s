pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    environment {
        AWS_REGION = 'ap-south-1'

        ECR_REGISTRY = '520701146276.dkr.ecr.ap-south-1.amazonaws.com'
        ECR_REPOSITORY = 'zero-downtime-app'

        K8S_NAMESPACE = 'zero-downtime'
        K8S_DEPLOYMENT = 'zero-downtime-app'

        ALB_URL = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'

        IMAGE_TAG = "${BUILD_NUMBER}"
        IMAGE_NAME = "520701146276.dkr.ecr.ap-south-1.amazonaws.com/zero-downtime-app:${BUILD_NUMBER}"
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm

                sh '''
                    set -e

                    echo "=========================================="
                    echo "SOURCE CHECKOUT"
                    echo "=========================================="

                    git rev-parse --short HEAD
                    git status --short
                '''
            }
        }

        stage('Test Application') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "APPLICATION TEST ENVIRONMENT"
                    echo "=========================================="

                    rm -rf .venv

                    python3 -m venv .venv

                    .venv/bin/python -m pip install \
                        --no-cache-dir \
                        -r app/requirements.txt

                    echo ""
                    echo "=========================================="
                    echo "APPLICATION SYNTAX CHECK"
                    echo "=========================================="

                    .venv/bin/python -m py_compile \
                        app/app.py \
                        app/test_app.py

                    echo "Application syntax check passed."

                    echo ""
                    echo "=========================================="
                    echo "APPLICATION UNIT TESTS"
                    echo "=========================================="

                    .venv/bin/python -m unittest discover \
                        -s app \
                        -p 'test_*.py' \
                        -v

                    echo ""
                    echo "=========================================="
                    echo "APPLICATION TESTS PASSED"
                    echo "=========================================="
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "DOCKER BUILD"
                    echo "=========================================="

                    docker build \
                        --build-arg APP_VERSION="${IMAGE_TAG}" \
                        -t "${IMAGE_NAME}" \
                        app/

                    echo "Docker image built successfully:"

                    docker images "${ECR_REGISTRY}/${ECR_REPOSITORY}" \
                        --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.Size}}"
                '''
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "TRIVY IMAGE VULNERABILITY SCAN"
                    echo "=========================================="

                    echo "Image: ${IMAGE_NAME}"

                    trivy image \
                        --scanners vuln \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \
                        --exit-code 1 \
                        --no-progress \
                        "${IMAGE_NAME}"

                    echo ""
                    echo "=========================================="
                    echo "TRIVY SCAN PASSED"
                    echo "=========================================="
                '''
            }
        }

        stage('ECR Login') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "ECR LOGIN"
                    echo "=========================================="

                    aws ecr get-login-password \
                        --region "${AWS_REGION}" \
                        | docker login \
                            --username AWS \
                            --password-stdin "${ECR_REGISTRY}"

                    echo "ECR login successful."
                '''
            }
        }

        stage('Push Image') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "PUSH IMAGE TO ECR"
                    echo "=========================================="

                    docker push "${IMAGE_NAME}"

                    echo ""
                    echo "Image pushed successfully:"
                    echo "${IMAGE_NAME}"

                    echo ""
                    echo "Image digest:"

                    docker inspect "${IMAGE_NAME}" \
                        --format '{{index .RepoDigests 0}}' || true
                '''
            }
        }

        stage('Kubernetes Access Check') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "KUBERNETES ACCESS CHECK"
                    echo "=========================================="

                    kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}"

                    echo "Kubernetes access check successful."
                '''
            }
        }

        stage('Capture Previous Image') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "CAPTURE CURRENT DEPLOYMENT IMAGE"
                    echo "=========================================="

                    rm -f .previous_image
                    rm -f .rollback_verified

                    kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}' \
                        > .previous_image

                    PREVIOUS_IMAGE=$(cat .previous_image)

                    echo "Previous image:"
                    echo "${PREVIOUS_IMAGE}"

                    if [ -z "${PREVIOUS_IMAGE}" ]; then
                        echo "ERROR: Previous image is empty."
                        exit 1
                    fi

                    case "${PREVIOUS_IMAGE}" in
                        "${ECR_REGISTRY}/${ECR_REPOSITORY}:"*)
                            echo "Previous image repository validated."
                            ;;
                        *)
                            echo "ERROR: Previous image does not belong to expected ECR repository."
                            echo "Expected repository: ${ECR_REGISTRY}/${ECR_REPOSITORY}"
                            echo "Actual image: ${PREVIOUS_IMAGE}"
                            exit 1
                            ;;
                    esac
                '''
            }
        }

        stage('Deploy') {
            steps {
                script {

                    sh '''
                        set -e

                        echo "=========================================="
                        echo "DEPLOY NEW IMAGE"
                        echo "=========================================="

                        echo "Previous image:"
                        cat .previous_image

                        echo ""
                        echo "New image:"
                        echo "${IMAGE_NAME}"

                        kubectl set image deployment/"${K8S_DEPLOYMENT}" \
                            app="${IMAGE_NAME}" \
                            -n "${K8S_NAMESPACE}"

                        echo ""
                        echo "Deployment image updated."
                    '''

                    int rolloutStatus = sh(
                        script: '''
                            set +e

                            echo "=========================================="
                            echo "WAIT FOR ROLLOUT"
                            echo "=========================================="

                            kubectl rollout status \
                                deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            STATUS=$?

                            echo ""
                            echo "Rollout command exit code: ${STATUS}"

                            exit ${STATUS}
                        ''',
                        returnStatus: true
                    )

                    if (rolloutStatus != 0) {

                        echo "Deployment rollout failed or timed out."
                        echo "Starting deterministic automatic rollback."

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "AUTOMATIC ROLLBACK"
                            echo "=========================================="

                            PREVIOUS_IMAGE=$(cat .previous_image)

                            echo "Restoring previous image:"
                            echo "${PREVIOUS_IMAGE}"

                            kubectl set image deployment/"${K8S_DEPLOYMENT}" \
                                app="${PREVIOUS_IMAGE}" \
                                -n "${K8S_NAMESPACE}"

                            echo ""
                            echo "Waiting for rollback rollout..."

                            kubectl rollout status \
                                deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            echo ""
                            echo "Rollback rollout completed."
                        '''

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "VERIFY RESTORED IMAGE"
                            echo "=========================================="

                            EXPECTED_IMAGE=$(cat .previous_image)

                            DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}')

                            echo "Expected image:"
                            echo "${EXPECTED_IMAGE}"

                            echo "Actual image:"
                            echo "${DEPLOYED_IMAGE}"

                            if [ "${DEPLOYED_IMAGE}" != "${EXPECTED_IMAGE}" ]; then
                                echo "ERROR: Rollback image verification failed."
                                exit 1
                            fi

                            echo "Rollback image verification passed."
                        '''

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "VERIFY READY REPLICAS"
                            echo "=========================================="

                            READY_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}')

                            DESIRED_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}')

                            READY_REPLICAS=${READY_REPLICAS:-0}

                            echo "Ready replicas: ${READY_REPLICAS}"
                            echo "Desired replicas: ${DESIRED_REPLICAS}"

                            if [ "${READY_REPLICAS}" -ne "${DESIRED_REPLICAS}" ]; then
                                echo "ERROR: Not all replicas are ready after rollback."
                                exit 1
                            fi

                            echo "All replicas are ready."
                        '''

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "VERIFY ALB HEALTH AFTER ROLLBACK"
                            echo "=========================================="

                            HTTP_CODE=$(curl \
                                -sS \
                                -o /tmp/alb-health-response \
                                -w "%{http_code}" \
                                --max-time 15 \
                                "${ALB_URL}/health")

                            echo "ALB /health HTTP status: ${HTTP_CODE}"

                            if [ "${HTTP_CODE}" != "200" ]; then
                                echo "ERROR: ALB health check failed after rollback."
                                cat /tmp/alb-health-response || true
                                exit 1
                            fi

                            echo "ALB health check passed."
                        '''

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "VERIFY ALB SERVES RESTORED VERSION"
                            echo "=========================================="

                            RESPONSE=$(curl \
                                -sS \
                                --max-time 15 \
                                "${ALB_URL}/")

                            EXPECTED_IMAGE=$(cat .previous_image)
                            EXPECTED_TAG="${EXPECTED_IMAGE##*:}"

                            echo "Expected restored version: ${EXPECTED_TAG}"
                            echo "ALB response:"
                            echo "${RESPONSE}"

                            if ! echo "${RESPONSE}" | grep -q \
                                "Application Version: <strong>${EXPECTED_TAG}</strong>"; then
                                echo "ERROR: ALB is not serving the restored version."
                                exit 1
                            fi

                            echo "ALB is serving the restored version."
                        '''

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "VERIFY FAILED VERSION IS NOT SERVED"
                            echo "=========================================="

                            RESPONSE=$(curl \
                                -sS \
                                --max-time 15 \
                                "${ALB_URL}/")

                            if echo "${RESPONSE}" | grep -q \
                                "Application Version: <strong>${IMAGE_TAG}</strong>"; then
                                echo "ERROR: Failed version ${IMAGE_TAG} is still being served."
                                exit 1
                            fi

                            echo "Failed version ${IMAGE_TAG} is not being served."
                        '''

                        sh '''
                            set -e

                            echo "=========================================="
                            echo "AUTOMATIC ROLLBACK VERIFIED"
                            echo "=========================================="

                            touch .rollback_verified
                        '''

                        error("Deployment failed. Automatic rollback completed and verified.")
                    }

                    echo "Deployment rollout completed successfully."
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "VERIFY DEPLOYMENT"
                    echo "=========================================="

                    DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    READY_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.status.readyReplicas}')

                    DESIRED_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.replicas}')

                    READY_REPLICAS=${READY_REPLICAS:-0}

                    echo "Deployed image:"
                    echo "${DEPLOYED_IMAGE}"

                    echo "Ready replicas:"
                    echo "${READY_REPLICAS}"

                    echo "Desired replicas:"
                    echo "${DESIRED_REPLICAS}"

                    if [ "${READY_REPLICAS}" -ne "${DESIRED_REPLICAS}" ]; then
                        echo "ERROR: Ready replica count does not match desired replica count."
                        exit 1
                    fi

                    if [ -f .rollback_verified ]; then

                        EXPECTED_IMAGE=$(cat .previous_image)

                        if [ "${DEPLOYED_IMAGE}" != "${EXPECTED_IMAGE}" ]; then
                            echo "ERROR: Restored image does not match expected previous image."
                            exit 1
                        fi

                        echo "Rollback image verification passed."

                    else

                        if [ "${DEPLOYED_IMAGE}" != "${IMAGE_NAME}" ]; then
                            echo "ERROR: Deployment image does not match new image."
                            exit 1
                        fi

                        echo "New deployment image verification passed."
                    fi

                    echo "Deployment verification passed."
                '''
            }
        }

        stage('ALB Smoke Test') {
            steps {
                sh '''
                    set -e

                    echo "=========================================="
                    echo "ALB SMOKE TEST"
                    echo "=========================================="

                    HTTP_CODE=$(curl \
                        -sS \
                        -o /tmp/alb-response \
                        -w "%{http_code}" \
                        --max-time 15 \
                        "${ALB_URL}/health")

                    echo "ALB /health HTTP status: ${HTTP_CODE}"

                    if [ "${HTTP_CODE}" != "200" ]; then
                        echo "ERROR: ALB health check failed."
                        cat /tmp/alb-response || true
                        exit 1
                    fi

                    RESPONSE=$(curl \
                        -sS \
                        --max-time 15 \
                        "${ALB_URL}/")

                    echo ""
                    echo "ALB application response:"
                    echo "${RESPONSE}"

                    DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    DEPLOYED_TAG="${DEPLOYED_IMAGE##*:}"

                    echo ""
                    echo "Actual deployed version: ${DEPLOYED_TAG}"

                    if [ "${DEPLOYED_TAG}" = "${IMAGE_TAG}" ]; then

                        echo "Detected successful new deployment."

                        if ! echo "${RESPONSE}" | grep -q \
                            "Application Version: <strong>${IMAGE_TAG}</strong>"; then
                            echo "ERROR: ALB is not serving the newly deployed version."
                            exit 1
                        fi

                        echo "ALB is serving the new version."
                        echo "ALB smoke test passed."

                    else

                        EXPECTED_IMAGE=$(cat .previous_image)
                        EXPECTED_TAG="${EXPECTED_IMAGE##*:}"

                        echo "Detected automatic rollback."
                        echo "Expected restored version: ${EXPECTED_TAG}"

                        if [ "${DEPLOYED_IMAGE}" != "${EXPECTED_IMAGE}" ]; then
                            echo "ERROR: Deployment image does not match rollback image."
                            exit 1
                        fi

                        if ! echo "${RESPONSE}" | grep -q \
                            "Application Version: <strong>${EXPECTED_TAG}</strong>"; then
                            echo "ERROR: ALB is not serving the restored version."
                            exit 1
                        fi

                        if echo "${RESPONSE}" | grep -q \
                            "Application Version: <strong>${IMAGE_TAG}</strong>"; then
                            echo "ERROR: Failed version is still being served."
                            exit 1
                        fi

                        echo "ALB is serving the restored version."
                        echo "Failed version is not being served."
                        echo "ALB rollback smoke test passed."
                    fi
                '''
            }
        }
    }

    post {
        success {
            script {
                if (fileExists('.rollback_verified')) {

                    String restoredImage = sh(
                        script: 'cat .previous_image',
                        returnStdout: true
                    ).trim()

                    echo "=========================================="
                    echo "PIPELINE SUCCESSFUL"
                    echo "=========================================="
                    echo "Deployment failed its rollout."
                    echo "Automatic rollback was completed and verified."
                    echo "Restored image: ${restoredImage}"

                } else {

                    String deployedImage = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "=========================================="
                    echo "PIPELINE SUCCESSFUL"
                    echo "=========================================="
                    echo "Deployment completed successfully."
                    echo "Deployed image: ${deployedImage}"
                }
            }
        }

        failure {
            script {
                if (fileExists('.rollback_verified')) {

                    String restoredImage = sh(
                        script: 'cat .previous_image',
                        returnStdout: true
                    ).trim()

                    echo "=========================================="
                    echo "PIPELINE FAILED AFTER AUTOMATIC ROLLBACK"
                    echo "=========================================="
                    echo "The deployment failed."
                    echo "Automatic rollback was completed and verified."
                    echo "Restored image: ${restoredImage}"

                } else {

                    echo "=========================================="
                    echo "PIPELINE FAILED"
                    echo "=========================================="
                    echo "Automatic rollback was not verified."
                }
            }
        }

        always {
            sh '''
                rm -rf .venv
                rm -f .previous_image
                rm -f .rollback_verified
            '''
        }
    }
}
