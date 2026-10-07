pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    environment {
        AWS_REGION = 'ap-south-1'

        EKS_CLUSTER = 'zero-downtime-eks'
        K8S_NAMESPACE = 'zero-downtime'
        K8S_DEPLOYMENT = 'zero-downtime-app'
        K8S_CONTAINER = 'app'

        ECR_REGISTRY = '520701146276.dkr.ecr.ap-south-1.amazonaws.com'
        ECR_REPOSITORY = 'zero-downtime-app'

        IMAGE_NAME = "520701146276.dkr.ecr.ap-south-1.amazonaws.com/zero-downtime-app:${BUILD_NUMBER}"

        ALB_URL = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Test Application') {
            steps {
                sh '''
                    set -e

                    echo "========================================="
                    echo "Testing application"
                    echo "========================================="

                    python3 -m py_compile app/app.py

                    echo "Application syntax check passed."
                '''
            }
        }

        stage('Build Docker Image') {
            steps {
                sh '''
                    set -e

                    echo "========================================="
                    echo "Building Docker image"
                    echo "========================================="

                    docker build \
                        --build-arg APP_VERSION="${BUILD_NUMBER}" \
                        -t "${IMAGE_NAME}" \
                        app/

                    echo "Docker image built successfully:"
                    echo "${IMAGE_NAME}"
                '''
            }
        }

        stage('Login to ECR') {
            steps {
                sh '''
                    set -e

                    echo "========================================="
                    echo "Logging in to Amazon ECR"
                    echo "========================================="

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

                    echo "========================================="
                    echo "Pushing Docker image to ECR"
                    echo "========================================="

                    docker push "${IMAGE_NAME}"

                    echo "Image pushed successfully:"
                    echo "${IMAGE_NAME}"
                '''
            }
        }

        stage('Deploy') {
            steps {
                script {

                    sh '''
                        set -e

                        echo "========================================="
                        echo "Updating kubeconfig"
                        echo "========================================="

                        aws eks update-kubeconfig \
                            --region "${AWS_REGION}" \
                            --name "${EKS_CLUSTER}"

                        echo "Kubeconfig updated successfully."

                        echo "========================================="
                        echo "Checking Kubernetes access"
                        echo "========================================="

                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}"

                        echo "Kubernetes access check successful."
                    '''

                    sh '''
                        set -eu

                        echo "========================================="
                        echo "Preparing deployment state"
                        echo "========================================="

                        rm -f .rollback_verified
                        rm -f .previous_image

                        echo "Capturing current deployment image..."

                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}' \
                            > .previous_image

                        if [ ! -s .previous_image ]; then
                            echo "ERROR: Previous image could not be captured."
                            exit 1
                        fi

                        PREVIOUS_IMAGE=$(cat .previous_image)
                        PREVIOUS_VERSION="${PREVIOUS_IMAGE##*:}"

                        echo "Previous image:"
                        echo "${PREVIOUS_IMAGE}"

                        echo "Previous version:"
                        echo "${PREVIOUS_VERSION}"

                        if [ -z "${PREVIOUS_VERSION}" ]; then
                            echo "ERROR: Previous image version is empty."
                            exit 1
                        fi

                        case "${PREVIOUS_IMAGE}" in
                            "${ECR_REGISTRY}/${ECR_REPOSITORY}:"*)
                                ;;
                            *)
                                echo "ERROR: Previous image does not belong to expected ECR repository."
                                echo "Image: ${PREVIOUS_IMAGE}"
                                exit 1
                                ;;
                        esac
                    '''

                    sh '''
                        set -e

                        PREVIOUS_IMAGE=$(cat .previous_image)
                        PREVIOUS_VERSION="${PREVIOUS_IMAGE##*:}"

                        echo "========================================="
                        echo "Current deployment state"
                        echo "========================================="

                        echo "Previous image  : ${PREVIOUS_IMAGE}"
                        echo "Previous version: ${PREVIOUS_VERSION}"
                        echo "New image       : ${IMAGE_NAME}"
                        echo "New version     : ${BUILD_NUMBER}"

                        echo "========================================="
                    '''

                    int rolloutStatus = sh(
                        script: '''
                            set +e

                            echo "========================================="
                            echo "Deploying new image"
                            echo "========================================="

                            kubectl set image \
                                deployment/"${K8S_DEPLOYMENT}" \
                                "${K8S_CONTAINER}"="${IMAGE_NAME}" \
                                -n "${K8S_NAMESPACE}"

                            echo "Deployment updated to:"
                            echo "${IMAGE_NAME}"

                            echo "========================================="
                            echo "Waiting for rollout"
                            echo "========================================="

                            kubectl rollout status \
                                deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            STATUS=$?

                            echo "Rollout status: ${STATUS}"

                            exit "${STATUS}"
                        ''',
                        returnStatus: true
                    )

                    if (rolloutStatus == 0) {

                        echo "========================================="
                        echo "ROLLOUT SUCCESSFUL"
                        echo "========================================="

                    } else {

                        echo "========================================="
                        echo "ROLLOUT FAILED"
                        echo "Starting automatic rollback"
                        echo "========================================="

                        sh '''
                            set -eu

                            if [ ! -s .previous_image ]; then
                                echo "ERROR: Previous image state is missing."
                                exit 1
                            fi

                            PREVIOUS_IMAGE=$(cat .previous_image)

                            echo "Restoring exact previous image:"
                            echo "${PREVIOUS_IMAGE}"

                            kubectl set image \
                                deployment/"${K8S_DEPLOYMENT}" \
                                "${K8S_CONTAINER}"="${PREVIOUS_IMAGE}" \
                                -n "${K8S_NAMESPACE}"

                            echo "Waiting for rollback rollout..."

                            kubectl rollout status \
                                deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            echo "Rollback rollout completed."
                        '''

                        sh '''
                            set -eu

                            EXPECTED_IMAGE=$(cat .previous_image)

                            ACTUAL_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}')

                            echo "Expected restored image:"
                            echo "${EXPECTED_IMAGE}"

                            echo "Actual deployed image:"
                            echo "${ACTUAL_IMAGE}"

                            if [ "${ACTUAL_IMAGE}" != "${EXPECTED_IMAGE}" ]; then
                                echo "ERROR: Exact previous image was not restored."
                                exit 1
                            fi

                            echo "Exact previous image restored successfully."
                        '''

                        sh '''
                            set -eu

                            READY_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}')

                            DESIRED_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}')

                            READY_REPLICAS="${READY_REPLICAS:-0}"

                            echo "Ready replicas   : ${READY_REPLICAS}"
                            echo "Desired replicas : ${DESIRED_REPLICAS}"

                            if [ "${READY_REPLICAS}" != "${DESIRED_REPLICAS}" ]; then
                                echo "ERROR: Rollback replicas are not healthy."
                                exit 1
                            fi

                            echo "Rollback replicas healthy: ${READY_REPLICAS}/${DESIRED_REPLICAS}"
                        '''

                        sh '''
                            set -eu

                            echo "========================================="
                            echo "Checking ALB health"
                            echo "========================================="

                            HTTP_CODE=$(curl -s \
                                -o /tmp/alb-health-response.txt \
                                -w "%{http_code}" \
                                "${ALB_URL}/health")

                            echo "ALB health HTTP status: ${HTTP_CODE}"

                            if [ "${HTTP_CODE}" != "200" ]; then
                                echo "ERROR: ALB health check failed."
                                exit 1
                            fi

                            echo "ALB health check passed."
                        '''

                        sh '''
                            set -eu

                            PREVIOUS_IMAGE=$(cat .previous_image)
                            PREVIOUS_VERSION="${PREVIOUS_IMAGE##*:}"

                            RESPONSE=$(curl -s "${ALB_URL}/")

                            echo "ALB application response:"
                            echo "${RESPONSE}"

                            echo "${RESPONSE}" | grep -q "<strong>${PREVIOUS_VERSION}</strong>"

                            if echo "${RESPONSE}" | grep -q "<strong>${BUILD_NUMBER}</strong>"; then
                                echo "ERROR: Failed version ${BUILD_NUMBER} is still being served."
                                exit 1
                            fi

                            echo "ALB rollback verification passed."
                            echo "Restored version ${PREVIOUS_VERSION} is being served."
                            echo "Failed version ${BUILD_NUMBER} is not being served."
                        '''

                        touchFile = sh(
                            script: 'touch .rollback_verified',
                            returnStatus: true
                        )

                        if (touchFile != 0) {
                            error('Failed to create rollback verification marker.')
                        }

                        echo "========================================="
                        echo "AUTOMATIC ROLLBACK VERIFIED"
                        echo "========================================="
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -eu

                    DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    READY_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.status.readyReplicas}')

                    DESIRED_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.replicas}')

                    READY_REPLICAS="${READY_REPLICAS:-0}"

                    echo "========================================="
                    echo "Deployment verification"
                    echo "========================================="

                    echo "Deployed image  : ${DEPLOYED_IMAGE}"
                    echo "Ready replicas  : ${READY_REPLICAS}"
                    echo "Desired replicas: ${DESIRED_REPLICAS}"

                    echo "========================================="

                    if [ "${READY_REPLICAS}" != "${DESIRED_REPLICAS}" ]; then
                        echo "ERROR: Ready replica count does not match desired replicas."
                        exit 1
                    fi

                    if [ "${DEPLOYED_IMAGE}" = "${IMAGE_NAME}" ]; then

                        echo "Deployment contains the new image."

                    elif [ -s .previous_image ] && \
                         [ "${DEPLOYED_IMAGE}" = "$(cat .previous_image)" ]; then

                        echo "Deployment contains the restored previous image."

                    else

                        echo "ERROR: Deployment image does not match expected state."
                        exit 1

                    fi

                    echo "Deployment verification passed."
                '''
            }
        }

        stage('ALB Smoke Test') {
            steps {
                sh '''
                    set -eu

                    DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    echo "========================================="
                    echo "ALB Smoke Test"
                    echo "========================================="

                    echo "Currently deployed image:"
                    echo "${DEPLOYED_IMAGE}"

                    echo "========================================="

                    if [ "${DEPLOYED_IMAGE}" = "${IMAGE_NAME}" ]; then

                        echo "Deployment state: NEW VERSION"

                        HTTP_CODE=$(curl -s \
                            -o /tmp/alb-smoke-response.txt \
                            -w "%{http_code}" \
                            "${ALB_URL}/health")

                        if [ "${HTTP_CODE}" != "200" ]; then
                            echo "ERROR: ALB health check failed."
                            exit 1
                        fi

                        RESPONSE=$(curl -s "${ALB_URL}/")

                        echo "ALB response:"
                        echo "${RESPONSE}"

                        echo "${RESPONSE}" | grep -q "<strong>${BUILD_NUMBER}</strong>"

                        echo "ALB smoke test passed."
                        echo "Version ${BUILD_NUMBER} is being served."

                    elif [ -s .previous_image ] && \
                         [ "${DEPLOYED_IMAGE}" = "$(cat .previous_image)" ]; then

                        PREVIOUS_IMAGE=$(cat .previous_image)
                        RESTORED_VERSION="${PREVIOUS_IMAGE##*:}"

                        echo "Deployment state: AUTOMATIC ROLLBACK"
                        echo "Restored version: ${RESTORED_VERSION}"

                        HTTP_CODE=$(curl -s \
                            -o /tmp/alb-smoke-response.txt \
                            -w "%{http_code}" \
                            "${ALB_URL}/health")

                        if [ "${HTTP_CODE}" != "200" ]; then
                            echo "ERROR: ALB health check failed after rollback."
                            exit 1
                        fi

                        RESPONSE=$(curl -s "${ALB_URL}/")

                        echo "ALB response:"
                        echo "${RESPONSE}"

                        echo "${RESPONSE}" | grep -q "<strong>${RESTORED_VERSION}</strong>"

                        if echo "${RESPONSE}" | grep -q "<strong>${BUILD_NUMBER}</strong>"; then
                            echo "ERROR: Failed version ${BUILD_NUMBER} is still being served."
                            exit 1
                        fi

                        echo "ALB smoke test passed after rollback."
                        echo "Restored version ${RESTORED_VERSION} is being served."
                        echo "Failed version ${BUILD_NUMBER} is not being served."

                    else

                        echo "ERROR: Deployment is in an unexpected state."
                        exit 1

                    fi
                '''
            }
        }
    }

    post {

        always {
            sh '''
                set +e

                echo "========================================="
                echo "Cleaning up"
                echo "========================================="

                docker logout "${ECR_REGISTRY}"

                echo "Cleanup completed."
            '''
        }

        success {
            script {
                echo "========================================="
                echo "PIPELINE SUCCESSFUL"
                echo "========================================="

                if (fileExists('.rollback_verified')) {

                    echo "Automatic rollback was successfully completed and verified."

                    if (fileExists('.previous_image')) {
                        def restoredImage = readFile('.previous_image').trim()
                        echo "Restored image: ${restoredImage}"
                    }

                } else {

                    echo "Deployment completed successfully."

                    def deployedImage = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "Deployed image: ${deployedImage}"
                }

                echo "========================================="
            }
        }

        failure {
            script {
                echo "========================================="
                echo "PIPELINE FAILED"
                echo "========================================="

                if (fileExists('.rollback_verified')) {
                    echo "Automatic rollback was completed and verified before the pipeline failure."
                } else {
                    echo "Pipeline failed before automatic rollback verification was completed."
                }

                echo "========================================="
            }
        }
    }
}
