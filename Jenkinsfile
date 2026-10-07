pipeline {

    agent any

    environment {
        AWS_REGION       = 'ap-south-1'
        AWS_ACCOUNT_ID   = '520701146276'

        ECR_REPOSITORY   = 'zero-downtime-app'
        ECR_REGISTRY     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

        IMAGE_TAG        = "${BUILD_NUMBER}"
        IMAGE_NAME       = "${ECR_REGISTRY}/${ECR_REPOSITORY}:${IMAGE_TAG}"

        EKS_CLUSTER      = 'zero-downtime-eks'
        K8S_NAMESPACE    = 'zero-downtime'
        K8S_DEPLOYMENT   = 'zero-downtime-app'
        K8S_CONTAINER    = 'app'

        ALB_URL          = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'

        ROLLBACK_PERFORMED = 'false'
    }

    stages {

        stage('Checkout') {
            steps {
                echo "========================================"
                echo "Checking out source code"
                echo "========================================"

                checkout scm
            }
        }

        stage('Test Application') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Testing Application"
                    echo "========================================"

                    python3 --version

                    echo ""
                    echo "Application files:"
                    ls -la app/

                    echo ""
                    echo "Checking Python syntax:"
                    python3 -m py_compile app/app.py

                    echo ""
                    echo "Application test passed."
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

                    docker build \
                        --build-arg APP_VERSION="${IMAGE_TAG}" \
                        -t "${IMAGE_NAME}" \
                        ./app

                    echo ""
                    echo "Docker image built successfully:"
                    docker images "${ECR_REGISTRY}/${ECR_REPOSITORY}"
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

                    echo "ECR login successful."
                '''
            }
        }

        stage('Push Image to ECR') {
            steps {
                sh '''
                    set -e

                    echo "========================================"
                    echo "Pushing Image to ECR"
                    echo "========================================"

                    docker push "${IMAGE_NAME}"

                    echo ""
                    echo "Image pushed successfully:"
                    echo "${IMAGE_NAME}"
                '''
            }
        }

        stage('Deploy to EKS') {
            steps {
                script {

                    sh '''
                        set -e

                        echo "========================================"
                        echo "Configuring Kubernetes Access"
                        echo "========================================"

                        aws eks update-kubeconfig \
                            --region "${AWS_REGION}" \
                            --name "${EKS_CLUSTER}"

                        echo ""
                        echo "Current Kubernetes context:"
                        kubectl config current-context

                        echo ""
                        echo "Kubernetes access check:"

                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}"
                    '''

                    /*
                     * Capture the currently deployed image.
                     *
                     * This image will be restored if the new
                     * deployment fails.
                     */
                    def previousImage = sh(
                        script: '''
                            kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}'
                        ''',
                        returnStdout: true
                    ).trim()

                    echo "========================================"
                    echo "Current Deployment Image"
                    echo "========================================"
                    echo "${previousImage}"

                    if (!previousImage) {
                        error(
                            "Unable to determine current deployment image. " +
                            "Aborting deployment."
                        )
                    }

                    env.PREVIOUS_IMAGE = previousImage

                    echo "========================================"
                    echo "Deploying New Image"
                    echo "========================================"

                    echo "New image:      ${IMAGE_NAME}"
                    echo "Previous image: ${previousImage}"

                    sh '''
                        set -e

                        echo "Updating deployment image..."

                        kubectl set image deployment/"${K8S_DEPLOYMENT}" \
                            "${K8S_CONTAINER}"="${IMAGE_NAME}" \
                            -n "${K8S_NAMESPACE}"

                        echo ""
                        echo "Deployment image updated."

                        echo ""
                        echo "Current deployment image:"

                        kubectl get deployment "${K8S_DEPLOYMENT}" \
                            -n "${K8S_NAMESPACE}" \
                            -o jsonpath='{.spec.template.spec.containers[0].image}'

                        echo
                    '''

                    /*
                     * Wait for the new deployment.
                     *
                     * returnStatus=true allows the pipeline to
                     * handle the failed rollout and perform the
                     * automatic rollback.
                     */
                    int rolloutStatus = sh(
                        script: '''
                            set +e

                            echo "========================================"
                            echo "Waiting for Deployment Rollout"
                            echo "========================================"

                            kubectl rollout status deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            STATUS=$?

                            echo ""
                            echo "Rollout exit status: ${STATUS}"

                            exit ${STATUS}
                        ''',
                        returnStatus: true
                    )

                    if (rolloutStatus != 0) {

                        echo "========================================"
                        echo "DEPLOYMENT FAILED"
                        echo "========================================"

                        echo "Failed image:"
                        echo "${IMAGE_NAME}"

                        echo ""
                        echo "Previous healthy image:"
                        echo "${previousImage}"

                        echo ""
                        echo "Starting automatic rollback..."

                        /*
                         * Restore the exact previous image.
                         */
                        sh """
                            set -e

                            echo "========================================"
                            echo "Automatic Rollback"
                            echo "========================================"

                            echo "Restoring image:"
                            echo "${previousImage}"

                            kubectl set image deployment/"${K8S_DEPLOYMENT}" \
                                "${K8S_CONTAINER}"="${previousImage}" \
                                -n "${K8S_NAMESPACE}"

                            echo ""
                            echo "Rollback image update submitted."

                            echo ""
                            echo "Waiting for rollback rollout..."

                            kubectl rollout status deployment/"${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            echo ""
                            echo "Rollback rollout completed successfully."
                        """

                        /*
                         * Verify that the exact previous image
                         * has been restored.
                         */
                        def restoredImage = sh(
                            script: '''
                                kubectl get deployment "${K8S_DEPLOYMENT}" \
                                    -n "${K8S_NAMESPACE}" \
                                    -o jsonpath='{.spec.template.spec.containers[0].image}'
                            ''',
                            returnStdout: true
                        ).trim()

                        echo "========================================"
                        echo "Verifying Rollback Image"
                        echo "========================================"

                        echo "Expected image:"
                        echo "${previousImage}"

                        echo ""
                        echo "Restored image:"
                        echo "${restoredImage}"

                        if (restoredImage != previousImage) {
                            error(
                                "Rollback verification failed. " +
                                "Expected ${previousImage}, " +
                                "but found ${restoredImage}"
                            )
                        }

                        echo ""
                        echo "Rollback image verification passed."

                        /*
                         * Verify all replicas are healthy.
                         */
                        sh '''
                            set -e

                            echo ""
                            echo "========================================"
                            echo "Verifying Kubernetes Pods"
                            echo "========================================"

                            kubectl get pods \
                                -n "${K8S_NAMESPACE}" \
                                -o wide

                            READY_COUNT=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}')

                            DESIRED_COUNT=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}')

                            echo ""
                            echo "Ready replicas:   ${READY_COUNT}"
                            echo "Desired replicas: ${DESIRED_COUNT}"

                            if [ "${READY_COUNT}" != "${DESIRED_COUNT}" ]; then
                                echo ""
                                echo "Rollback pod verification failed."
                                exit 1
                            fi

                            echo ""
                            echo "All deployment replicas are healthy."
                        '''

                        /*
                         * Verify ALB health.
                         */
                        sh '''
                            set -e

                            echo ""
                            echo "========================================"
                            echo "Verifying ALB Health"
                            echo "========================================"

                            HTTP_STATUS=$(curl \
                                -s \
                                -o /tmp/alb-health-response \
                                -w "%{http_code}" \
                                --max-time 30 \
                                "${ALB_URL}/health")

                            echo "HTTP status: ${HTTP_STATUS}"

                            if [ "${HTTP_STATUS}" != "200" ]; then
                                echo ""
                                echo "ALB health verification failed."
                                cat /tmp/alb-health-response || true
                                exit 1
                            fi

                            echo ""
                            echo "ALB health check passed."
                        '''

                        /*
                         * Verify that the failed version is no longer
                         * being served through the ALB.
                         *
                         * Build #14 is intentionally testing rollback
                         * from :14 back to the known healthy :7.
                         */
                        sh """
                            set -e

                            echo ""
                            echo "========================================"
                            echo "Verifying Application Through ALB"
                            echo "========================================"

                            RESPONSE=\$(curl \
                                -s \
                                --max-time 30 \
                                "${ALB_URL}/")

                            echo "\${RESPONSE}"

                            echo ""
                            echo "Checking failed version..."

                            if echo "\${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                                echo ""
                                echo "ERROR: Failed version ${IMAGE_TAG} is still being served."
                                exit 1
                            fi

                            echo ""
                            echo "Checking restored version..."

                            if ! echo "\${RESPONSE}" | grep -q "<strong>7</strong>"; then
                                echo ""
                                echo "ERROR: Expected restored application version 7 was not served."
                                exit 1
                            fi

                            echo ""
                            echo "Failed version is no longer being served."
                            echo "Restored version is being served."
                        """

                        /*
                         * Mark rollback as successfully verified.
                         */
                        env.ROLLBACK_PERFORMED = 'true'

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

                    } else {

                        echo ""
                        echo "========================================"
                        echo "DEPLOYMENT SUCCESSFUL"
                        echo "========================================"

                        echo "Image deployed successfully:"
                        echo "${IMAGE_NAME}"

                        echo "========================================"
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

                    DEPLOYED_IMAGE=$(kubectl get deployment "${K8S_DEPLOYMENT}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    echo "${DEPLOYED_IMAGE}"
                '''
            }
        }

        stage('ALB Smoke Test') {
            steps {
                script {

                    if (env.ROLLBACK_PERFORMED == 'true') {

                        echo ""
                        echo "========================================"
                        echo "ALB Smoke Test"
                        echo "========================================"

                        echo "Automatic rollback already verified:"

                        echo "- Kubernetes rollback verified"
                        echo "- Pod health verified"
                        echo "- ALB health verified"
                        echo "- Restored application verified"
                        echo "- Failed version no longer served"

                        echo ""
                        echo "Skipping normal deployment version assertion."

                    } else {

                        sh '''
                            set -e

                            echo "========================================"
                            echo "ALB Smoke Test"
                            echo "========================================"

                            echo "Testing ALB health endpoint..."

                            HTTP_STATUS=$(curl \
                                -s \
                                -o /tmp/alb-health \
                                -w "%{http_code}" \
                                --max-time 30 \
                                "${ALB_URL}/health")

                            echo "Health HTTP status: ${HTTP_STATUS}"

                            if [ "${HTTP_STATUS}" != "200" ]; then
                                echo ""
                                echo "ALB health check failed."
                                cat /tmp/alb-health || true
                                exit 1
                            fi

                            echo ""
                            echo "Testing application endpoint..."

                            RESPONSE=$(curl \
                                -s \
                                --max-time 30 \
                                "${ALB_URL}/")

                            echo "${RESPONSE}"

                            echo ""
                            echo "Validating deployed application version..."

                            if ! echo "${RESPONSE}" | grep -q "<strong>${IMAGE_TAG}</strong>"; then
                                echo ""
                                echo "Expected application version ${IMAGE_TAG} was not found."
                                exit 1
                            fi

                            echo ""
                            echo "ALB smoke test passed."
                        '''
                    }
                }
            }
        }
    }

    post {

        success {
            script {

                echo ""
                echo "========================================"
                echo "JENKINS PIPELINE SUCCESS"
                echo "========================================"

                if (env.ROLLBACK_PERFORMED == 'true') {

                    echo "Deployment result: FAILED"
                    echo "Recovery result:   SUCCESSFUL"
                    echo "Rollback result:   VERIFIED"

                    echo ""
                    echo "The failed deployment was automatically"
                    echo "rolled back and the previous healthy"
                    echo "version was restored successfully."

                } else {

                    echo "Deployment result: SUCCESSFUL"
                    echo "Rollback required: NO"

                    echo ""
                    echo "Application deployed successfully."
                }

                echo "========================================"
            }
        }

        failure {
            script {

                echo ""
                echo "========================================"
                echo "JENKINS PIPELINE FAILED"
                echo "========================================"

                if (env.ROLLBACK_PERFORMED == 'true') {

                    echo "Automatic rollback was performed."
                    echo "However, one or more verification steps failed."

                } else {

                    echo "Pipeline failed before automatic rollback"
                    echo "could be successfully verified."
                }

                echo "========================================"
            }
        }

        always {
            sh '''
                echo "========================================"
                echo "Cleaning Up"
                echo "========================================"

                docker logout "${ECR_REGISTRY}" || true

                rm -f .previous_image || true

                echo "Cleanup completed."
            '''
        }
    }
}
