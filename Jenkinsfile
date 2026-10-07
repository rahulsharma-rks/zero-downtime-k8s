pipeline {

    agent any

    options {
        skipDefaultCheckout(true)
        timestamps()
    }

    environment {
        AWS_REGION     = 'ap-south-1'
        EKS_CLUSTER     = 'zero-downtime-eks'
        K8S_NAMESPACE   = 'zero-downtime'
        K8S_DEPLOYMENT  = 'zero-downtime-app'
        K8S_CONTAINER    = 'app'

        ECR_REGISTRY    = '520701146276.dkr.ecr.ap-south-1.amazonaws.com'
        ECR_REPOSITORY  = 'zero-downtime-app'
        IMAGE_TAG       = "${BUILD_NUMBER}"
        IMAGE_NAME      = "520701146276.dkr.ecr.ap-south-1.amazonaws.com/zero-downtime-app:${BUILD_NUMBER}"

        ALB_DNS         = 'k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'

        PREVIOUS_IMAGE  = ''
        PREVIOUS_VERSION = ''
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

                    /*
                     * ---------------------------------------------------------
                     * Kubernetes access
                     * ---------------------------------------------------------
                     */
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
                     * ---------------------------------------------------------
                     * Capture the currently deployed image.
                     *
                     * Kubernetes is the source of truth.
                     * Do not proceed if the image cannot be determined.
                     * ---------------------------------------------------------
                     */
                    def previousImage = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        ''',
                        returnStdout: true
                    ).trim()

                    if (!previousImage) {
                        error(
                            "Could not determine the current deployment image. " +
                            "Refusing to deploy because automatic rollback would be unsafe."
                        )
                    }

                    def previousVersion = previousImage.tokenize(':').last()

                    env.PREVIOUS_IMAGE = previousImage
                    env.PREVIOUS_VERSION = previousVersion

                    echo "========================================="
                    echo "Current deployment state"
                    echo "========================================="
                    echo "Previous image  : ${env.PREVIOUS_IMAGE}"
                    echo "Previous version: ${env.PREVIOUS_VERSION}"
                    echo "New image       : ${env.IMAGE_NAME}"
                    echo "New version     : ${env.IMAGE_TAG}"
                    echo "========================================="

                    /*
                     * ---------------------------------------------------------
                     * Deploy new version.
                     *
                     * We intentionally use returnStatus so that a failed
                     * rollout can enter the automatic rollback path.
                     * ---------------------------------------------------------
                     */
                    int status = sh(
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

                            exit ${STATUS}
                        ''',
                        returnStatus: true
                    )

                    /*
                     * ---------------------------------------------------------
                     * Automatic rollback
                     * ---------------------------------------------------------
                     */
                    if (status != 0) {

                        echo "========================================="
                        echo "ROLLOUT FAILED"
                        echo "Starting automatic rollback"
                        echo "========================================="

                        if (!env.PREVIOUS_IMAGE?.trim()) {
                            error(
                                "Previous image is empty. " +
                                "Refusing to perform unsafe rollback."
                            )
                        }

                        sh '''
                            set -e

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

                        /*
                         * -----------------------------------------------------
                         * Verify exact image restoration
                         * -----------------------------------------------------
                         */
                        def restoredImage = sh(
                            script: '''
                                kubectl get deployment "${K8S_DEPLOYMENT}" \
                                    -n "${K8S_NAMESPACE}" \
                                    -o jsonpath='{.spec.template.spec.containers[0].image}'
                            ''',
                            returnStdout: true
                        ).trim()

                        if (restoredImage != env.PREVIOUS_IMAGE) {
                            error(
                                "Rollback image verification failed. " +
                                "Expected ${env.PREVIOUS_IMAGE}, " +
                                "got ${restoredImage}"
                            )
                        }

                        echo "Exact previous image restored successfully:"
                        echo "${restoredImage}"

                        /*
                         * -----------------------------------------------------
                         * Verify Ready replicas
                         * -----------------------------------------------------
                         */
                        def readyReplicas = sh(
                            script: '''
                                kubectl get deployment "${K8S_DEPLOYMENT}" \
                                    -n "${K8S_NAMESPACE}" \
                                    -o jsonpath='{.status.readyReplicas}'
                            ''',
                            returnStdout: true
                        ).trim()

                        def desiredReplicas = sh(
                            script: '''
                                kubectl get deployment "${K8S_DEPLOYMENT}" \
                                    -n "${K8S_NAMESPACE}" \
                                    -o jsonpath='{.spec.replicas}'
                            ''',
                            returnStdout: true
                        ).trim()

                        if (readyReplicas != desiredReplicas) {
                            error(
                                "Rollback replica verification failed. " +
                                "Ready=${readyReplicas}, " +
                                "Desired=${desiredReplicas}"
                            )
                        }

                        echo "Rollback replicas healthy:"
                        echo "${readyReplicas}/${desiredReplicas}"

                        /*
                         * -----------------------------------------------------
                         * Verify ALB health
                         * -----------------------------------------------------
                         */
                        sh '''
                            set -e

                            echo "========================================="
                            echo "Checking ALB health"
                            echo "========================================="

                            HTTP_CODE=$(curl -s \
                                -o /tmp/alb-health-response.txt \
                                -w "%{http_code}" \
                                "http://${ALB_DNS}/health")

                            echo "ALB health HTTP status: ${HTTP_CODE}"

                            if [ "${HTTP_CODE}" != "200" ]; then
                                echo "ERROR: ALB health check failed."
                                cat /tmp/alb-health-response.txt
                                exit 1
                            fi

                            echo "ALB health check passed."
                        '''

                        /*
                         * -----------------------------------------------------
                         * Verify ALB serves restored version and not failed
                         * version.
                         * -----------------------------------------------------
                         */
                        sh '''
                            set -e

                            echo "========================================="
                            echo "Verifying ALB application version"
                            echo "========================================="

                            RESPONSE=$(curl -s "http://${ALB_DNS}/")

                            echo "ALB application response:"
                            echo "${RESPONSE}"

                            echo "${RESPONSE}" | grep -q \
                                "<strong>${PREVIOUS_VERSION}</strong>" || {
                                    echo "ERROR: ALB is not serving restored version ${PREVIOUS_VERSION}"
                                    exit 1
                                }

                            if echo "${RESPONSE}" | grep -q \
                                "<strong>${IMAGE_TAG}</strong>"; then

                                echo "ERROR: Failed version ${IMAGE_TAG} is still being served by ALB."
                                exit 1
                            fi

                            echo "ALB rollback verification passed."
                            echo "Restored version ${PREVIOUS_VERSION} is being served."
                            echo "Failed version ${IMAGE_TAG} is not being served."
                        '''

                        env.ROLLBACK_PERFORMED = 'true'

                        echo "========================================="
                        echo "AUTOMATIC ROLLBACK VERIFIED"
                        echo "========================================="
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {

                    def deployedImage = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        ''',
                        returnStdout: true
                    ).trim()

                    def readyReplicas = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}'
                        ''',
                        returnStdout: true
                    ).trim()

                    def desiredReplicas = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}'
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "========================================="
                    echo "Deployment verification"
                    echo "========================================="
                    echo "Deployed image : ${deployedImage}"
                    echo "Ready replicas : ${readyReplicas}"
                    echo "Desired replicas: ${desiredReplicas}"
                    echo "========================================="

                    if (readyReplicas != desiredReplicas) {
                        error(
                            "Deployment verification failed. " +
                            "Ready=${readyReplicas}, Desired=${desiredReplicas}"
                        )
                    }

                    if (
                        deployedImage != env.IMAGE_NAME &&
                        deployedImage != env.PREVIOUS_IMAGE
                    ) {
                        error(
                            "Unexpected deployed image: ${deployedImage}. " +
                            "Expected ${env.IMAGE_NAME} or ${env.PREVIOUS_IMAGE}"
                        )
                    }

                    echo "Deployment verification passed."
                }
            }
        }

        stage('ALB Smoke Test') {
            steps {
                script {

                    def deployedImage = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "========================================="
                    echo "ALB Smoke Test"
                    echo "========================================="
                    echo "Currently deployed image:"
                    echo "${deployedImage}"
                    echo "========================================="

                    /*
                     * ---------------------------------------------------------
                     * Normal successful deployment path
                     * ---------------------------------------------------------
                     */
                    if (deployedImage == env.IMAGE_NAME) {

                        sh '''
                            set -e

                            echo "Testing ALB health..."

                            HTTP_CODE=$(curl -s \
                                -o /tmp/alb-smoke-response.txt \
                                -w "%{http_code}" \
                                "http://${ALB_DNS}/health")

                            if [ "${HTTP_CODE}" != "200" ]; then
                                echo "ERROR: ALB health check failed."
                                cat /tmp/alb-smoke-response.txt
                                exit 1
                            fi

                            RESPONSE=$(curl -s "http://${ALB_DNS}/")

                            echo "ALB response:"
                            echo "${RESPONSE}"

                            echo "${RESPONSE}" | grep -q \
                                "<strong>${IMAGE_TAG}</strong>" || {
                                    echo "ERROR: Expected version ${IMAGE_TAG} was not served by ALB."
                                    exit 1
                                }

                            echo "ALB smoke test passed."
                            echo "Version ${IMAGE_TAG} is being served."
                        '''
                    }

                    /*
                     * ---------------------------------------------------------
                     * Automatic rollback path
                     * ---------------------------------------------------------
                     */
                    else if (deployedImage == env.PREVIOUS_IMAGE) {

                        def restoredVersion = env.PREVIOUS_IMAGE.tokenize(':').last()

                        withEnv([
                            "RESTORED_VERSION=${restoredVersion}"
                        ]) {

                            sh '''
                                set -e

                                echo "Deployment is in rollback state."
                                echo "Restored version: ${RESTORED_VERSION}"

                                echo "Testing ALB health..."

                                HTTP_CODE=$(curl -s \
                                    -o /tmp/alb-smoke-response.txt \
                                    -w "%{http_code}" \
                                    "http://${ALB_DNS}/health")

                                if [ "${HTTP_CODE}" != "200" ]; then
                                    echo "ERROR: ALB health check failed after rollback."
                                    cat /tmp/alb-smoke-response.txt
                                    exit 1
                                fi

                                RESPONSE=$(curl -s "http://${ALB_DNS}/")

                                echo "ALB response:"
                                echo "${RESPONSE}"

                                echo "${RESPONSE}" | grep -q \
                                    "<strong>${RESTORED_VERSION}</strong>" || {
                                        echo "ERROR: ALB is not serving restored version ${RESTORED_VERSION}."
                                        exit 1
                                    }

                                if echo "${RESPONSE}" | grep -q \
                                    "<strong>${IMAGE_TAG}</strong>"; then

                                    echo "ERROR: Failed version ${IMAGE_TAG} is still being served."
                                    exit 1
                                fi

                                echo "ALB smoke test passed after rollback."
                                echo "Restored version ${RESTORED_VERSION} is being served."
                                echo "Failed version ${IMAGE_TAG} is not being served."
                            '''
                        }
                    }

                    else {
                        error(
                            "ALB Smoke Test found unexpected deployment image: " +
                            "${deployedImage}"
                        )
                    }
                }
            }
        }
    }

    post {

        success {
            script {
                echo "========================================="
                echo "PIPELINE SUCCESSFUL"
                echo "========================================="

                if (env.ROLLBACK_PERFORMED == 'true') {
                    echo "Automatic rollback was successfully completed and verified."
                    echo "Restored image: ${env.PREVIOUS_IMAGE}"
                } else {
                    echo "Deployment completed successfully."
                    echo "Deployed image: ${env.IMAGE_NAME}"
                }

                echo "========================================="
            }
        }

        failure {
            script {
                echo "========================================="
                echo "PIPELINE FAILED"
                echo "========================================="

                if (env.ROLLBACK_PERFORMED == 'true') {
                    echo "Automatic rollback was completed before the pipeline failed during a later verification stage."
                    echo "Restored image: ${env.PREVIOUS_IMAGE}"
                } else {
                    echo "Automatic rollback was not successfully completed."
                }

                echo "========================================="
            }
        }

        always {
            sh '''
                set +e

                echo "========================================="
                echo "Cleaning up"
                echo "========================================="

                docker logout "${ECR_REGISTRY}" >/dev/null 2>&1 || true

                echo "Cleanup completed."
            '''
        }
    }
}
