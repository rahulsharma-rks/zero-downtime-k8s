pipeline {
    agent any

    options {
        skipDefaultCheckout(true)
        disableConcurrentBuilds()
        timestamps()
    }

    environment {
        AWS_REGION = 'ap-south-1'
        AWS_ACCOUNT_ID = '520701146276'
        ECR_REPOSITORY = 'zero-downtime-app'
        EKS_CLUSTER = 'zero-downtime-eks'
        K8S_NAMESPACE = 'zero-downtime'
        DEPLOYMENT_NAME = 'zero-downtime-app'
        CONTAINER_NAME = 'app'

        IMAGE_NAME = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPOSITORY}:${BUILD_NUMBER}"
        ECR_REGISTRY = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

        ALB_URL = 'http://k8s-zerodown-zerodown-2877ae3841-1074707335.ap-south-1.elb.amazonaws.com'
    }

    stages {

        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: '*/main']],
                    userRemoteConfigs: [[
                        url: 'https://github.com/rahulsharma-rks/zero-downtime-k8s.git',
                        credentialsId: 'github-zero-downtime'
                    ]]
                ])
            }
        }

        stage('Setup Python Environment') {
            steps {
                sh '''
                    set -e

                    python3 -m venv .venv

                    .venv/bin/pip install --upgrade pip

                    .venv/bin/pip install -r app/requirements.txt
                '''
            }
        }

        stage('Unit Tests') {
            steps {
                sh '''
                    set -e

                    .venv/bin/python -m unittest discover \
                        -s app \
                        -p 'test_*.py' \
                        -v
                '''
            }
        }

        stage('Docker Build') {
            steps {
                sh '''
                    set -e

                    echo "Building Docker image:"
                    echo "${IMAGE_NAME}"

                    docker buildx build \
                        --build-arg APP_VERSION="${BUILD_NUMBER}" \
                        --tag "${IMAGE_NAME}" \
                        --provenance=false \
                        --load \
                        app/
                '''
            }
        }

        stage('Trivy Image Scan') {
            steps {
                sh '''
                    set -e

                    trivy image \
                        --scanners vuln \
                        --severity HIGH,CRITICAL \
                        --ignore-unfixed \
                        --exit-code 1 \
                        --no-progress \
                        "${IMAGE_NAME}"
                '''
            }
        }

        stage('ECR Login') {
            steps {
                sh '''
                    set -e

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

                    docker push "${IMAGE_NAME}"

                    echo "Pushed image:"
                    echo "${IMAGE_NAME}"

                    echo "Image digest:"

                    docker inspect \
                        --format='{{index .RepoDigests 0}}' \
                        "${IMAGE_NAME}"
                '''
            }
        }

        stage('ECR Scan Verification') {
            steps {
                sh '''
                    set -e

                    echo "Waiting for Amazon ECR image scan results..."

                    IMAGE_TAG="${BUILD_NUMBER}"
                    MAX_ATTEMPTS=12
                    ATTEMPT=1

                    while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do

                        echo "ECR scan check attempt ${ATTEMPT}/${MAX_ATTEMPTS}"

                        if aws ecr describe-image-scan-findings \
                            --repository-name "${ECR_REPOSITORY}" \
                            --image-id imageTag="${IMAGE_TAG}" \
                            --region "${AWS_REGION}" \
                            > ecr-scan.json 2>/tmp/ecr-scan-error; then

                            echo "ECR scan results available."

                            python3 -c '
import json

with open("ecr-scan.json") as f:
    data = json.load(f)

scan = data.get("imageScanFindings", {})

findings = scan.get("findings", [])
counts = scan.get("findingSeverityCounts", {})

high = int(counts.get("HIGH", 0))
critical = int(counts.get("CRITICAL", 0))

print("")
print("========================================")
print("ECR SECURITY SCAN SUMMARY")
print("========================================")
print(f"HIGH     : {high}")
print(f"CRITICAL : {critical}")
print("========================================")

interesting = [
    finding
    for finding in findings
    if finding.get("severity") in {"HIGH", "CRITICAL"}
]

if not interesting:
    print("")
    print("No HIGH or CRITICAL ECR findings.")
else:
    print("")
    print("HIGH / CRITICAL FINDINGS")
    print("----------------------------------------")

    for finding in interesting:
        severity = finding.get("severity", "N/A")
        name = finding.get("name", "N/A")
        uri = finding.get("uri", "N/A")
        description = finding.get("description", "N/A")

        print(f"Severity     : {severity}")
        print(f"Finding      : {name}")
        print(f"Package URI  : {uri}")
        print(f"Description  : {description}")
        print("----------------------------------------")

print("")
print("Policy: report-only.")
print("Trivy remains the blocking security gate.")
'

                            echo "ECR scan verification completed."

                            break
                        fi

                        echo "ECR scan results not ready yet."

                        cat /tmp/ecr-scan-error || true

                        ATTEMPT=$((ATTEMPT + 1))

                        if [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; then
                            sleep 10
                        fi

                    done

                    if [ "${ATTEMPT}" -gt "${MAX_ATTEMPTS}" ]; then
                        echo "ECR scan results were not available within the expected time."
                        exit 1
                    fi
                '''
            }
        }

        stage('Capture Previous Image') {
            steps {
                sh '''
                    set -e

                    rm -f .previous_image
                    rm -f .rollback_verified

                    CURRENT_IMAGE=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                        -n "${K8S_NAMESPACE}" \
                        -o jsonpath='{.spec.template.spec.containers[0].image}')

                    echo "Current production image:"
                    echo "${CURRENT_IMAGE}"

                    printf '%s' "${CURRENT_IMAGE}" > .previous_image

                    echo "Previous image captured:"
                    cat .previous_image
                '''
            }
        }

        stage('Deploy') {
            steps {
                script {
                    try {
                        sh '''
                            set -e

                            echo "Deploying image:"
                            echo "${IMAGE_NAME}"

                            kubectl set image deployment/"${DEPLOYMENT_NAME}" \
                                "${CONTAINER_NAME}"="${IMAGE_NAME}" \
                                -n "${K8S_NAMESPACE}"

                            kubectl rollout status deployment/"${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m
                        '''
                    } catch (err) {

                        echo "Deployment failed. Starting deterministic automatic rollback."

                        sh '''
                            set -e

                            PREVIOUS_IMAGE=$(cat .previous_image)

                            echo "Rolling back to:"
                            echo "${PREVIOUS_IMAGE}"

                            kubectl set image deployment/"${DEPLOYMENT_NAME}" \
                                "${CONTAINER_NAME}"="${PREVIOUS_IMAGE}" \
                                -n "${K8S_NAMESPACE}"

                            kubectl rollout status deployment/"${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=5m

                            RESTORED_IMAGE=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}')

                            echo "Restored deployment image:"
                            echo "${RESTORED_IMAGE}"

                            if [ "${RESTORED_IMAGE}" != "${PREVIOUS_IMAGE}" ]; then
                                echo "Rollback image verification failed."
                                exit 1
                            fi

                            READY_REPLICAS=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}')

                            DESIRED_REPLICAS=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}')

                            echo "Ready replicas after rollback: ${READY_REPLICAS}"
                            echo "Desired replicas: ${DESIRED_REPLICAS}"

                            if [ "${READY_REPLICAS}" != "${DESIRED_REPLICAS}" ]; then
                                echo "Rollback replica verification failed."
                                exit 1
                            fi

                            HTTP_STATUS=$(curl \
                                --silent \
                                --output /dev/null \
                                --write-out '%{http_code}' \
                                --max-time 10 \
                                "${ALB_URL}/health")

                            echo "ALB /health status after rollback: ${HTTP_STATUS}"

                            if [ "${HTTP_STATUS}" != "200" ]; then
                                echo "ALB health verification failed after rollback."
                                exit 1
                            fi

                            ALB_VERSION=$(curl \
                                --silent \
                                --max-time 10 \
                                "${ALB_URL}/" \
                                | sed -n 's/.*Application Version: <strong>\\([^<]*\\)<\\/strong>.*/\\1/p')

                            EXPECTED_VERSION=$(printf '%s' "${PREVIOUS_IMAGE}" \
                                | awk -F: '{print $NF}')

                            echo "ALB version after rollback: ${ALB_VERSION}"
                            echo "Expected version: ${EXPECTED_VERSION}"

                            if [ "${ALB_VERSION}" != "${EXPECTED_VERSION}" ]; then
                                echo "ALB version verification failed after rollback."
                                exit 1
                            fi

                            FAILED_VERSION=$(printf '%s' "${IMAGE_NAME}" \
                                | awk -F: '{print $NF}')

                            echo "Failed deployment version: ${FAILED_VERSION}"

                            if [ "${ALB_VERSION}" = "${FAILED_VERSION}" ]; then
                                echo "Failed version is still being served by ALB."
                                exit 1
                            fi

                            touch .rollback_verified

                            echo "AUTOMATIC ROLLBACK VERIFIED"
                        '''

                        error("Deployment failed. Automatic rollback completed and verified.")
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                script {

                    if (fileExists('.rollback_verified')) {

                        echo "Skipping normal deployment verification because automatic rollback was verified."

                    } else {

                        sh '''
                            set -e

                            echo "Verifying successful deployment..."

                            kubectl rollout status deployment/"${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                --timeout=2m

                            CURRENT_IMAGE=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.template.spec.containers[0].image}')

                            echo "Current deployment image:"
                            echo "${CURRENT_IMAGE}"

                            if [ "${CURRENT_IMAGE}" != "${IMAGE_NAME}" ]; then
                                echo "Deployment image verification failed."
                                exit 1
                            fi

                            READY_REPLICAS=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.status.readyReplicas}')

                            DESIRED_REPLICAS=$(kubectl get deployment "${DEPLOYMENT_NAME}" \
                                -n "${K8S_NAMESPACE}" \
                                -o jsonpath='{.spec.replicas}')

                            echo "Ready replicas: ${READY_REPLICAS}"
                            echo "Desired replicas: ${DESIRED_REPLICAS}"

                            if [ "${READY_REPLICAS}" != "${DESIRED_REPLICAS}" ]; then
                                echo "Replica verification failed."
                                exit 1
                            fi

                            HTTP_STATUS=$(curl \
                                --silent \
                                --output /dev/null \
                                --write-out '%{http_code}' \
                                --max-time 10 \
                                "${ALB_URL}/health")

                            echo "ALB /health status: ${HTTP_STATUS}"

                            if [ "${HTTP_STATUS}" != "200" ]; then
                                echo "ALB health verification failed."
                                exit 1
                            fi

                            echo "Deployment verification successful."
                        '''
                    }
                }
            }
        }
    }

    post {

        success {
            script {

                if (fileExists('.rollback_verified')) {

                    echo "Build succeeded with rollback verification marker present."

                } else {

                    echo "Deployment completed successfully."

                }
            }
        }

        failure {
            script {

                if (fileExists('.rollback_verified')) {

                    echo "AUTOMATIC ROLLBACK VERIFIED."
                    echo "The deployment failed as expected and the previous healthy version was restored successfully."

                } else {

                    echo "Build failed without a verified automatic rollback."

                }
            }
        }

        cleanup {
            sh '''
                rm -rf .venv
                rm -f .previous_image
                rm -f .rollback_verified
                rm -f ecr-scan.json
                rm -f /tmp/ecr-scan-error
            '''
        }
    }
}
