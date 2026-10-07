pipeline {

    agent any

    options {
        skipDefaultCheckout(true)
    }

    environment {
        AWS_REGION      = 'ap-south-1'
        AWS_ACCOUNT_ID  = '520701146276'

        ECR_REPOSITORY  = 'zero-downtime-app'
        ECR_REGISTRY    = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        IMAGE_TAG       = "${BUILD_NUMBER}"
        IMAGE_NAME      = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

        EKS_CLUSTER     = 'zero-downtime-eks'
        K8S_NAMESPACE   = 'zero-downtime'
        K8S_DEPLOYMENT  = 'zero-downtime-app'
        K8S_CONTAINER   = 'app'

        ALB_URL         = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'

        ROLLBACK_PERFORMED = 'false'
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
                        --build-arg APP_VERSION="${IMAGE_TAG}" \
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
                        --region "${AWS_REGION}" | \
                    docker login \
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

                    /*
                     * Capture the exact image currently deployed.
                     * This becomes the rollback target.
                     */
                    def previousImage = sh(
                        script: """
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        """,
                        returnStdout: true
                    ).trim()

                    if (!previousImage) {
                        error("Unable to determine current deployment image.")
                    }

                    env.PREVIOUS_IMAGE = previousImage

                    /*
                     * Dynamically extract the previous version.
                     *
                     * Example:
                     * .../zero-downtime-app:7
                     * -> 7
                     */
                    def previousVersion = previousImage.tokenize(':').last()
                    env.PREVIOUS_VERSION = previousVersion

                    echo "========================================="
                    echo "Current deployment state"
                    echo "========================================="
                    echo "Previous image  : ${previousImage}"
                    echo "Previous version: ${previousVersion}"
                    echo "New image       : ${env.IMAGE_NAME}"
                    echo "New version     : ${env.IMAGE_TAG}"
                    echo "========================================="

                    sh """
                        set -e

                        echo "========================================="
                        echo "Deploying new image"
                        echo "========================================="

                        kubectl set image deployment/"${K8S_DEPLOYMENT}" \
                            "${K8S_CONTAINER}"="${IMAGE_NAME}" \
                            -n "${K8S_NAMESPACE}"

                        echo "Deployment updated to:"
                        echo "${IMAGE_NAME}"

                        echo "========================================="
                        echo "Waiting for rollout"
                        echo "========================================="

                        set +e

                        kubectl rollout status \
                            deployment/"${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}" \
                            --timeout=5m

                        ROLLOUT_STATUS=\$?

                        set -e

                        if [ "\${ROLLOUT_STATUS}" -eq 0 ]; then

                            echo "========================================="
                            echo "ROLLOUT SUCCESSFUL"
                            echo "========================================="

                        else

                            echo "========================================="
                            echo "ROLLOUT FAILED"
                            echo "Starting automatic rollback"
                            echo "========================================="

                            echo "Restoring exact previous image:"
                            echo "${previousImage}"

                            kubectl set image deployment/"${K8S_DEPLOYMENT}" \
                                "${K8S_CONTAINER}"="${previousImage}" \
                                -n "${K8S_NAMESPACE}"

                            echo "Waiting for rollback rollout..."

                            kubectl rollout status \
                                deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            echo "Rollback rollout completed successfully."

                            echo "========================================="
                            echo "Verifying restored image"
                            echo "========================================="

                            RESTORED_IMAGE=\$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}')

                            echo "Expected image: ${previousImage}"
                            echo "Actual image  : \${RESTORED_IMAGE}"

                            if [ "\${RESTORED_IMAGE}" != "${previousImage}" ]; then
                                echo "ERROR: Deployment did not restore the previous image."
                                exit 1
                            fi

                            echo "Restored image verification passed."

                            echo "========================================="
                            echo "Verifying ready replicas"
                            echo "========================================="

                            READY_REPLICAS=\$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}')

                            DESIRED_REPLICAS=\$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}')

                            READY_REPLICAS=\${READY_REPLICAS:-0}

                            echo "Ready replicas   : \${READY_REPLICAS}"
                            echo "Desired replicas : \${DESIRED_REPLICAS}"

                            if [ "\${READY_REPLICAS}" -ne "\${DESIRED_REPLICAS}" ]; then
                                echo "ERROR: Not all replicas are ready after rollback."
                                exit 1
                            fi

                            echo "Replica verification passed."

                            echo "========================================="
                            echo "Verifying ALB health after rollback"
                            echo "========================================="

                            ALB_HEALTH_STATUS=\$(curl \
                                --silent \
                                --output /dev/null \
                                --write-out "%{http_code}" \
                                --max-time 10 \
                                "${ALB_URL}/health")

                            echo "ALB /health HTTP status: \${ALB_HEALTH_STATUS}"

                            if [ "\${ALB_HEALTH_STATUS}" != "200" ]; then
                                echo "ERROR: ALB health check failed after rollback."
                                exit 1
                            fi

                            echo "ALB health verification passed."

                            echo "========================================="
                            echo "Verifying restored version through ALB"
                            echo "========================================="

                            RESPONSE=\$(curl \
                                --silent \
                                --max-time 10 \
                                "${ALB_URL}/")

                            echo "ALB application response:"
                            echo "\${RESPONSE}"

                            RESTORED_VERSION="${previousVersion}"

                            if ! echo "\${RESPONSE}" | grep -q "<strong>\${RESTORED_VERSION}</strong>"; then
                                echo "ERROR: ALB is not serving the restored version."
                                echo "Expected restored version: \${RESTORED_VERSION}"
                                exit 1
                            fi

                            if echo "\${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                                echo "ERROR: Failed deployment version ${IMAGE_TAG} is still being served by ALB."
                                exit 1
                            fi

                            echo "ALB restored-version verification passed."
                            echo "Failed version ${IMAGE_TAG} is no longer being served."

                            echo "========================================="
                            echo "AUTOMATIC ROLLBACK VERIFIED"
                            echo "========================================="

                            echo "Failed version   : ${IMAGE_TAG}"
                            echo "Restored version : \${RESTORED_VERSION}"
                            echo "Restored image   : ${previousImage}"

                            /*
                             * Durable workspace marker.
                             * Used by later stages and post actions.
                             */
                            touch .rollback_verified

                            exit 0
                        fi
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh '''
                    set -e

                    echo "========================================="
                    echo "Verifying Kubernetes deployment"
                    echo "========================================="

                    DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    echo "Deployed image:"
                    echo "${DEPLOYED_IMAGE}"

                    READY_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.status.readyReplicas}')

                    DESIRED_REPLICAS=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.replicas}')

                    READY_REPLICAS=${READY_REPLICAS:-0}

                    echo "Ready replicas   : ${READY_REPLICAS}"
                    echo "Desired replicas : ${DESIRED_REPLICAS}"

                    if [ "${READY_REPLICAS}" -ne "${DESIRED_REPLICAS}" ]; then
                        echo "ERROR: Deployment does not have all replicas ready."
                        exit 1
                    fi

                    echo "Deployment verification passed."
                '''
            }
        }

        stage('ALB Smoke Test') {
            steps {
                script {

                    echo "========================================="
                    echo "ALB STATE-BASED SMOKE TEST"
                    echo "========================================="

                    /*
                     * Kubernetes Deployment state is the source of truth.
                     * Do not rely on ROLLBACK_PERFORMED here.
                     */
                    def deployedImage = sh(
                        script: """
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        """,
                        returnStdout: true
                    ).trim()

                    echo "Expected new image   : ${env.IMAGE_NAME}"
                    echo "Previous image       : ${env.PREVIOUS_IMAGE}"
                    echo "Actual deployed image: ${deployedImage}"

                    if (deployedImage == env.IMAGE_NAME) {

                        /*
                         * NORMAL DEPLOYMENT
                         */
                        echo "========================================="
                        echo "STATE: NORMAL DEPLOYMENT"
                        echo "========================================="

                        echo "Deployment image matches IMAGE_NAME."
                        echo "Expecting new version: ${env.IMAGE_TAG}"

                        sh '''
                            set -e

                            echo "Checking ALB /health..."

                            ALB_HEALTH_STATUS=$(curl \
                                --silent \
                                --output /dev/null \
                                --write-out "%{http_code}" \
                                --max-time 10 \
                                "${ALB_URL}/health")

                            echo "ALB /health HTTP status: ${ALB_HEALTH_STATUS}"

                            if [ "${ALB_HEALTH_STATUS}" != "200" ]; then
                                echo "ERROR: ALB health check failed."
                                exit 1
                            fi

                            echo "Checking application version..."

                            RESPONSE=$(curl \
                                --silent \
                                --max-time 10 \
                                "${ALB_URL}/")

                            echo "ALB application response:"
                            echo "${RESPONSE}"

                            if ! echo "${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                                echo "ERROR: ALB is not serving the expected new version."
                                echo "Expected version: ${IMAGE_TAG}"
                                exit 1
                            fi

                            echo "ALB is serving the expected new version."
                        '''

                        env.ROLLBACK_PERFORMED = 'false'

                    } else if (deployedImage == env.PREVIOUS_IMAGE) {

                        /*
                         * ROLLBACK
                         */
                        echo "========================================="
                        echo "STATE: ROLLBACK"
                        echo "========================================="

                        echo "Deployment image does NOT match IMAGE_NAME."
                        echo "Deployment image matches PREVIOUS_IMAGE."
                        echo "Automatic rollback is confirmed."

                        def restoredVersion = env.PREVIOUS_IMAGE.tokenize(':').last()

                        echo "Restored image  : ${env.PREVIOUS_IMAGE}"
                        echo "Restored version: ${restoredVersion}"

                        sh """
                            set -e

                            echo "Checking ALB /health after rollback..."

                            ALB_HEALTH_STATUS=\$(curl \
                                --silent \
                                --output /dev/null \
                                --write-out "%{http_code}" \
                                --max-time 10 \
                                "${ALB_URL}/health")

                            echo "ALB /health HTTP status: \${ALB_HEALTH_STATUS}"

                            if [ "\${ALB_HEALTH_STATUS}" != "200" ]; then
                                echo "ERROR: ALB health check failed after rollback."
                                exit 1
                            fi

                            echo "Checking restored application version..."

                            RESPONSE=\$(curl \
                                --silent \
                                --max-time 10 \
                                "${ALB_URL}/")

                            echo "ALB application response:"
                            echo "\${RESPONSE}"

                            if ! echo "\${RESPONSE}" | grep -q "<strong>${restoredVersion}</strong>"; then
                                echo "ERROR: ALB is not serving the restored version."
                                echo "Expected restored version: ${restoredVersion}"
                                exit 1
                            fi

                            if echo "\${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                                echo "ERROR: Failed deployment version ${IMAGE_TAG} is still being served."
                                exit 1
                            fi

                            echo "========================================="
                            echo "ROLLBACK ALB SMOKE TEST PASSED"
                            echo "========================================="

                            echo "Failed version   : ${IMAGE_TAG}"
                            echo "Restored version : ${restoredVersion}"
                            echo "Restored image   : ${env.PREVIOUS_IMAGE}"
                        """

                        env.ROLLBACK_PERFORMED = 'true'

                    } else {

                        /*
                         * UNEXPECTED DEPLOYMENT STATE
                         */
                        error(
                            "Unexpected deployment image. " +
                            "Expected either IMAGE_NAME (${env.IMAGE_NAME}) " +
                            "or PREVIOUS_IMAGE (${env.PREVIOUS_IMAGE}), " +
                            "but found: ${deployedImage}"
                        )
                    }
                }
            }
        }
    }

    post {

        success {
            script {
                if (fileExists('.rollback_verified')) {

                    echo "========================================="
                    echo "PIPELINE SUCCESSFUL"
                    echo "========================================="
                    echo "Deployment failed safely and was automatically rolled back."
                    echo "Failed version          : ${env.IMAGE_TAG}"
                    echo "Restored image          : ${env.PREVIOUS_IMAGE}"
                    echo "Restored version        : ${env.PREVIOUS_VERSION}"
                    echo "ALB rollback verification: PASSED"
                    echo "========================================="

                } else {

                    echo "========================================="
                    echo "PIPELINE SUCCESSFUL"
                    echo "========================================="
                    echo "Normal deployment completed successfully."
                    echo "Deployed image          : ${env.IMAGE_NAME}"
                    echo "ALB verification        : PASSED"
                    echo "========================================="
                }
            }
        }

        failure {
            script {
                if (fileExists('.rollback_verified')) {

                    echo "========================================="
                    echo "PIPELINE FAILED AFTER ROLLBACK"
                    echo "========================================="
                    echo "Automatic rollback was successfully verified."
                    echo "Restored image          : ${env.PREVIOUS_IMAGE}"
                    echo "Restored version        : ${env.PREVIOUS_VERSION}"
                    echo "Failure occurred after rollback verification."
                    echo "========================================="

                } else {

                    echo "========================================="
                    echo "PIPELINE FAILED"
                    echo "========================================="
                    echo "Automatic rollback was not successfully verified."
                    echo "========================================="
                }
            }
        }

        always {
            sh '''
                set +e

                echo "========================================="
                echo "Cleaning up"
                echo "========================================="

                rm -f .previous_image
                rm -f .rollback_verified

                docker logout "${ECR_REGISTRY}" >/dev/null 2>&1 || true

                echo "Cleanup completed."
            '''
        }
    }
}
