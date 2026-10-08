readme = r'''# Zero-Downtime Kubernetes Deployment with Jenkins on AWS EKS

A production-style DevOps project demonstrating how to build, deploy, monitor, secure, and automatically roll back a containerized application on Amazon EKS using Jenkins, Terraform, Docker, Amazon ECR, Kubernetes, AWS Load Balancer Controller, Application Load Balancer, Trivy, Amazon CloudWatch, and Amazon SNS.

The project was built from scratch with an emphasis on Infrastructure as Code, CI/CD automation, zero-downtime rolling deployments, deterministic rollback, Kubernetes production hardening, container security, vulnerability investigation, and operational monitoring.

---

## Table of Contents

1. [Project Overview](#project-overview)
2. [Problem Statement](#problem-statement)
3. [Project Goals](#project-goals)
4. [Final Architecture](#final-architecture)
5. [Architecture Flow](#architecture-flow)
6. [Technology Stack](#technology-stack)
7. [Repository Structure](#repository-structure)
8. [Project Phases](#project-phases)
9. [Phase 1 - Infrastructure](#phase-1---infrastructure)
10. [Phase 2 - Amazon EKS](#phase-2---amazon-eks)
11. [Phase 3 - Kubernetes Application](#phase-3---kubernetes-application)
12. [Phase 4 - ALB and Networking](#phase-4---alb-and-networking)
13. [Phase 5 - Zero-Downtime Rolling Deployment](#phase-5---zero-downtime-rolling-deployment)
14. [Phase 6 - Jenkins CI/CD](#phase-6---jenkins-cicd)
15. [Phase 7 - Automated Rollback](#phase-7---automated-rollback)
16. [Phase 8 - Production Hardening](#phase-8---production-hardening)
17. [Phase 9 - Failure and Rollback Testing](#phase-9---failure-and-rollback-testing)
18. [Phase 10 - Security and CI/CD Hardening](#phase-10---security-and-cicd-hardening)
19. [Jenkins EC2 Setup](#jenkins-ec2-setup)
20. [Prerequisites](#prerequisites)
21. [AWS IAM Requirements](#aws-iam-requirements)
22. [Terraform Configuration](#terraform-configuration)
23. [Deploy Infrastructure](#deploy-infrastructure)
24. [Configure kubectl](#configure-kubectl)
25. [Install / Verify AWS Load Balancer Controller](#install--verify-aws-load-balancer-controller)
26. [Deploy Kubernetes Application](#deploy-kubernetes-application)
27. [Configure Jenkins](#configure-jenkins)
28. [Jenkins Pipeline](#jenkins-pipeline)
29. [Security Pipeline](#security-pipeline)
30. [Monitoring and Alerting](#monitoring-and-alerting)
31. [Useful Kubernetes Commands](#useful-kubernetes-commands)
32. [Useful AWS Commands](#useful-aws-commands)
33. [Replication Guide](#replication-guide)
34. [Terraform Destroy / Environment Cleanup](#terraform-destroy--environment-cleanup)
35. [Security Considerations](#security-considerations)
36. [What This Project Demonstrates](#what-this-project-demonstrates)
37. [Lessons Learned](#lessons-learned)
38. [Known Limitations](#known-limitations)
39. [Final Result](#final-result)
40. [Repository](#repository)

---

# Project Overview

The objective of this project was to build a realistic Kubernetes deployment platform rather than simply deploy a container to EKS.

The final platform provides:

- Infrastructure provisioning using Terraform
- Amazon VPC with public and private subnets
- Amazon EKS cluster
- EKS managed worker nodes
- Amazon ECR container registry
- Kubernetes application deployment
- AWS Load Balancer Controller
- AWS Application Load Balancer
- Kubernetes rolling deployment strategy
- Zero-downtime deployment behavior under normal rolling-update conditions
- Jenkins-based CI/CD
- Automated application rollback
- Kubernetes health checks
- Pod disruption protection
- Pod topology spreading
- Kubernetes security hardening
- Docker image vulnerability scanning with Trivy
- Amazon ECR vulnerability scanning
- Vulnerability investigation and remediation
- Amazon CloudWatch Container Insights
- CloudWatch alarms
- Amazon SNS notifications
- Infrastructure destruction using Terraform

The project was intentionally developed incrementally through **10 phases**.

---

# Problem Statement

A production deployment should not simply:

```text
Build Image
    ↓
Push Image
    ↓
kubectl apply
```

A production-oriented deployment needs to answer several questions:

- How is infrastructure created?
- How are containers built?
- How are images scanned?
- How does Kubernetes determine whether a new pod is healthy?
- How can a deployment avoid unnecessarily terminating healthy replicas?
- What happens if the new version becomes unhealthy?
- How can the system automatically return to the last known-good version?
- How are containers hardened?
- How are vulnerabilities identified and investigated?
- How are CPU, memory, restarts, and HTTP 5xx errors monitored?
- How are operators notified?
- How can the entire environment be recreated or destroyed?

This project was designed to answer those questions with working infrastructure and CI/CD automation.

---

# Project Goals

The primary goals were:

1. Build AWS infrastructure using Terraform.
2. Create an Amazon EKS cluster.
3. Deploy a containerized application.
4. Expose the application through an AWS Application Load Balancer.
5. Implement Kubernetes rolling deployments.
6. Configure the deployment for zero-downtime behavior under normal rolling-update conditions.
7. Build a Jenkins CI/CD pipeline.
8. Automatically detect deployment failures.
9. Automatically roll back failed deployments.
10. Harden the Kubernetes workload.
11. Scan container images for vulnerabilities.
12. Integrate Amazon ECR vulnerability scanning.
13. Investigate and remediate an actual container vulnerability.
14. Implement CloudWatch monitoring and SNS alerting.
15. Validate the complete failure and rollback workflow.
16. Make the infrastructure reproducible and removable with Terraform.

---

# Final Architecture

```text
                         Internet Users
                               |
                               v
                    +---------------------+
                    |   AWS ALB           |
                    | Application Load    |
                    | Balancer            |
                    +----------+----------+
                               |
                               v
                         Target Group
                         Target Type: IP
                               |
                               v
                    +---------------------+
                    |   EKS Pod IPs       |
                    |                     |
                    |  +---------------+  |
                    |  | Application   |  |
                    |  | Pod           |  |
                    |  +---------------+  |
                    |                     |
                    |  +---------------+  |
                    |  | Application   |  |
                    |  | Pod           |  |
                    |  +---------------+  |
                    |                     |
                    |  +---------------+  |
                    |  | Application   |  |
                    |  | Pod           |  |
                    |  +---------------+  |
                    +---------------------+

                             ^
                             |
                    Kubernetes Ingress
                             ^
                             |
              AWS Load Balancer Controller
                             ^
                             |
                       EKS Cluster
```

CI/CD path:

```text
Developer
    |
    v
GitHub
    |
    v
Jenkins
(Standalone Ubuntu EC2)
    |
    +--------------------------+
    |                          |
    v                          v
Terraform                  CI/CD Pipeline
    |                          |
    v                          v
AWS Infrastructure       Unit Tests
                               |
                               v
                         Docker BuildKit
                               |
                               v
                             Trivy
                               |
                               v
                              ECR
                               |
                               v
                      ECR Scan Verification
                               |
                               v
                         Kubernetes
                               |
                               v
                       Rolling Deployment
                               |
                      +--------+--------+
                      |                 |
                   Healthy           Failed
                      |                 |
                      v                 v
                  Continue          Rollback
```

---

# Architecture Flow

There are two separate flows in the project.

## Infrastructure Flow

Jenkins can execute Terraform to provision the AWS infrastructure:

```text
Jenkins
   |
   v
Terraform
   |
   +---- VPC
   |
   +---- Subnets
   |
   +---- NAT Gateway
   |
   +---- EKS
   |
   +---- Node Group
   |
   +---- ECR
   |
   +---- CloudWatch
   |
   +---- SNS
   |
   +---- IAM
```

## Application Traffic Flow

The application traffic path is:

```text
Internet
   |
   v
AWS Application Load Balancer
   |
   v
ALB Target Group
   |
   v
Pod IP
   |
   v
Application Container
```

Kubernetes `Ingress` does not represent the physical traffic path from the ALB to the application. Instead:

```text
Kubernetes Ingress
        |
        v
AWS Load Balancer Controller
        |
        v
AWS ALB / Target Group
```

The controller watches the Kubernetes resources and configures the corresponding AWS load-balancing resources.

---

# Technology Stack

| Component | Technology |
|---|---|
| Cloud | AWS |
| Region | `ap-south-1` |
| Infrastructure as Code | Terraform |
| Container Runtime | Docker |
| Container Build | Docker BuildKit / buildx |
| Container Registry | Amazon ECR |
| Kubernetes | Amazon EKS |
| Kubernetes Version | 1.36 |
| CI/CD | Jenkins |
| Jenkins Host | Standalone Ubuntu EC2 |
| Load Balancer | AWS Application Load Balancer |
| ALB Integration | AWS Load Balancer Controller |
| Security Scanner | Trivy |
| Container Vulnerability Scanner | Amazon ECR |
| Monitoring | Amazon CloudWatch |
| Kubernetes Monitoring | CloudWatch Container Insights |
| Alerting | Amazon SNS |
| Application | Python Flask |
| Application Port | 8080 |

---

# AWS Infrastructure

The environment was built using the following design.

## VPC

```text
VPC CIDR:
10.20.0.0/16
```

## Private Subnets

```text
10.20.1.0/24
10.20.2.0/24
```

## Public Subnets

```text
10.20.101.0/24
10.20.102.0/24
```

## NAT Gateway

One NAT Gateway was used for the private subnet egress path.

## EKS

```text
Cluster:
zero-downtime-eks

Kubernetes:
1.36
```

## Managed Node Group

```text
Instance Type: t3.small
Desired:       3
Minimum:       2
Maximum:       3
Disk:          20 GB
Capacity:      ON_DEMAND
```

---

# Repository Structure

```text
zero-downtime-k8s/
│
├── .gitignore
├── Jenkinsfile
├── iam_policy.json
│
├── app/
│   ├── Dockerfile
│   ├── app.py
│   ├── requirements.txt
│   └── test_app.py
│
├── k8s/
│   ├── deployment.yaml
│   ├── ingress.yaml
│   ├── pdb.yaml
│   └── service.yaml
│
└── terraform/
    ├── .terraform.lock.hcl
    ├── ecr.tf
    ├── eks.tf
    ├── outputs.tf
    ├── variables.tf
    ├── versions.tf
    ├── vpc.tf
    ├── cloudwatch_iam.tf
    ├── cloudwatch_logs.tf
    ├── cloudwatch_alarms.tf
    └── cloudwatch_notifications.tf
```

---

# Project Phases

The project consists of exactly **10 phases**.

```text
Phase 1  - Infrastructure
Phase 2  - Amazon EKS
Phase 3  - Kubernetes Application
Phase 4  - ALB / Networking
Phase 5  - Zero-Downtime Rolling Deployment
Phase 6  - Jenkins CI/CD
Phase 7  - Automated Rollback
Phase 8  - Production Hardening
Phase 9  - Failure / Rollback Testing
Phase 10 - Security & CI/CD Hardening
```

---

# Phase 1 - Infrastructure

Terraform was used to create the AWS foundation.

The infrastructure included:

- VPC
- Public subnets
- Private subnets
- Internet Gateway
- NAT Gateway
- Routing
- ECR
- IAM resources
- EKS prerequisites

Terraform modules used:

```text
terraform-aws-modules/vpc/aws
terraform-aws-modules/eks/aws
```

The project used:

```text
Terraform: 1.16.5
AWS Provider: 6.67.0
VPC Module: 6.7.3
EKS Module: 21.26.0
```

---

# Phase 2 - Amazon EKS

An Amazon EKS cluster was created:

```text
zero-downtime-eks
```

The cluster uses:

- Kubernetes 1.36
- EKS managed node group
- Three worker nodes
- EKS add-ons
- VPC networking
- CloudWatch observability

Configured EKS add-ons include:

```text
coredns
kube-proxy
vpc-cni
eks-pod-identity-agent
amazon-cloudwatch-observability
```

The final node-group configuration was:

```text
min_size     = 2
max_size     = 3
desired_size = 3
```

---

# Phase 3 - Kubernetes Application

A simple Flask application was created specifically for demonstrating deployment behavior.

The application exposes:

```text
/
```

```text
/health
```

```text
/ready
```

Example:

```python
@app.route("/health")
def health():
    return "OK", 200
```

Readiness can intentionally be failed using:

```text
READINESS_FAIL=true
```

This capability was added specifically to test Kubernetes deployment failure and automated rollback.

---

# Phase 4 - ALB / Networking

The application is exposed using Kubernetes `Ingress`.

The AWS Load Balancer Controller watches the Kubernetes Ingress and creates/manages the corresponding AWS Application Load Balancer.

The ALB uses:

```text
Target Type: IP
Health Check: /health
Success Code: 200
```

The resulting architecture is:

```text
Internet
    |
    v
AWS ALB
    |
    v
Target Group
    |
    v
Pod IPs
```

The application health endpoint is:

```text
/health
```

A successful request returns:

```text
HTTP 200
OK
```

---

# Phase 5 - Zero-Downtime Rolling Deployment

The Kubernetes Deployment uses:

```yaml
replicas: 3

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

This means Kubernetes attempts to maintain all three existing replicas available while introducing the new version.

During a normal update:

```text
Version N
Pod 1
Pod 2
Pod 3
```

A new pod is created:

```text
Version N
Pod 1
Pod 2
Pod 3

Version N+1
Pod 4
```

Once the new pod becomes Ready, Kubernetes can terminate an old pod.

The process continues until all replicas run the new version.

The important settings are:

```text
maxUnavailable = 0
maxSurge       = 1
replicas       = 3
```

This is a **zero-downtime deployment strategy under normal rolling-update conditions**. It should not be interpreted as an absolute guarantee against every possible infrastructure, networking, application, or dependency failure.

---

# Phase 6 - Jenkins CI/CD

Jenkins runs on a **standalone Ubuntu EC2 instance**.

Jenkins is intentionally outside the EKS cluster.

The Jenkins server performs two major functions.

## Infrastructure

```text
Terraform
```

for creating and destroying AWS infrastructure.

## CI/CD

```text
Git checkout
      ↓
Python environment
      ↓
Unit tests
      ↓
Docker BuildKit
      ↓
Trivy scan
      ↓
ECR login
      ↓
Push image
      ↓
ECR scan verification
      ↓
Kubernetes deployment
      ↓
Rollout verification
      ↓
ALB smoke test
```

---

# Phase 7 - Automated Rollback

The pipeline was designed to automatically restore the previous known-good image if a deployment fails.

Before deployment, Jenkins captures the currently running image.

Conceptually:

```text
Current Version
      |
      v
Capture Image
      |
      v
Deploy New Version
      |
      v
Wait for Rollout
      |
   +--+--+
   |     |
 PASS   FAIL
   |     |
   |     v
   |   Rollback
   |     |
   |     v
   | Previous Version
   |
   v
ALB Validation
```

Rollback uses the Kubernetes container name:

```text
app
```

For example:

```bash
kubectl set image deployment/zero-downtime-app \
  app="${ECR_REGISTRY}/${ECR_REPOSITORY}:${PREVIOUS_TAG}" \
  -n zero-downtime
```

The rollback is then verified using:

```bash
kubectl rollout status
```

followed by:

```bash
kubectl get deployment
```

and an external ALB health check.

---

# Phase 8 - Production Hardening

Several Kubernetes production-hardening features were added.

## Resource Requests and Limits

```yaml
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 250m
    memory: 256Mi
```

## Readiness Probe

```text
/ready
```

The pod receives traffic only when the readiness probe succeeds.

## Liveness Probe

```text
/health
```

The liveness probe helps Kubernetes identify an unhealthy container.

## Startup Probe

The application also has a startup probe to allow sufficient startup time before liveness enforcement becomes relevant.

## Pod Disruption Budget

```yaml
minAvailable: 2
```

With three replicas, the application attempts to maintain at least two available replicas during voluntary disruptions.

## Pod Topology Spread

Pods are spread across Kubernetes worker nodes using:

```text
kubernetes.io/hostname
```

This reduces the risk of concentrating all application replicas on one worker.

## Graceful Termination

The deployment uses:

```text
terminationGracePeriodSeconds: 30
```

and a pre-stop hook:

```text
sleep 10
```

This gives the pod time to drain before termination.

## Container Security Context

The application runs as a non-root user.

Configured controls include:

```text
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile: RuntimeDefault
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
```

A writable `emptyDir` volume is mounted at:

```text
/tmp
```

because the application filesystem is read-only.

---

# Phase 9 - Failure / Rollback Testing

The deployment system was deliberately tested under failure conditions.

The application supports:

```text
READINESS_FAIL=true
```

This causes:

```text
/ready
```

to return:

```text
HTTP 503
```

The deployment therefore cannot become Ready.

Kubernetes eventually reports the rollout as failed.

Jenkins detects this condition and executes the rollback logic.

The rollback was tested successfully.

The test demonstrated:

```text
New version
     ↓
Readiness failure
     ↓
Rollout failure
     ↓
Automatic rollback
     ↓
Previous image restored
     ↓
Deployment healthy
     ↓
ALB health check successful
```

---

# Phase 10 - Security & CI/CD Hardening

Phase 10 was the final phase.

It contained three major subphases.

## Phase 10.1 - BuildKit + ECR Scan Integration

Docker BuildKit was integrated into the Jenkins pipeline.

The image build uses:

```bash
docker buildx build \
  --build-arg APP_VERSION="${BUILD_NUMBER}" \
  --tag "${IMAGE_NAME}" \
  --provenance=false \
  --load \
  app/
```

The image is then scanned with Trivy.

## Phase 10.2 - ECR Vulnerability Reporting

Amazon ECR image scanning was integrated into the Jenkins pipeline.

ECR scanning is asynchronous, so Jenkins does not immediately assume that scan results are available.

The pipeline polls ECR for scan results.

The pipeline reports:

```text
HIGH
CRITICAL
```

findings.

The current policy is:

```text
Trivy       = blocking security gate
ECR scan    = report-only
```

Therefore:

- Trivy HIGH/CRITICAL findings block the build.
- ECR findings are reported for additional visibility.
- ECR scan availability itself is verified before continuing.

## Phase 10.3 - Vulnerability Investigation and Base Image Hardening

During testing, ECR reported a HIGH vulnerability:

```text
CVE-2026-85091
```

The finding was associated with the zlib package in the Debian-based Python image.

The investigation identified the affected package in:

```text
python:3.12-slim
```

An Alpine-based image was evaluated:

```text
python:3.12-alpine
```

The Alpine zlib package was upgraded:

```bash
apk update
apk upgrade zlib
```

The final Dockerfile contains:

```dockerfile
RUN apk update && \
    apk upgrade zlib && \
    rm -rf /var/cache/apk/*
```

The hardened image was then validated using:

```text
Unit tests
Trivy
Container execution
Health endpoint
Readiness endpoint
Non-root execution
Read-only filesystem
```

The resulting image had:

```text
HIGH     = 0
CRITICAL = 0
```

This phase demonstrated the complete vulnerability lifecycle:

```text
Detect
  ↓
Investigate
  ↓
Identify affected dependency
  ↓
Evaluate alternative base image
  ↓
Patch dependency
  ↓
Rebuild
  ↓
Rescan
  ↓
Deploy
```

---

# Final Dockerfile

The production Dockerfile is:

```dockerfile
FROM python:3.12-alpine

ARG APP_VERSION=dev

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_VERSION=${APP_VERSION}

RUN apk update && \
    apk upgrade zlib && \
    rm -rf /var/cache/apk/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN addgroup -S appgroup && \
    adduser -S -D -H -s /sbin/nologin -G appgroup appuser

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
```

The final application image does not include the unit-test source file.

---

# Jenkins EC2 Setup

Jenkins runs on a separate Ubuntu EC2 instance.

Architecture:

```text
Ubuntu EC2
     |
     +---- Jenkins
     |
     +---- Git
     |
     +---- Docker
     |
     +---- AWS CLI
     |
     +---- kubectl
     |
     +---- Terraform
     |
     +---- Trivy
     |
     +---- Python
```

Jenkins is **not deployed inside EKS**.

This separation allows Jenkins to act as an external CI/CD control plane.

---

# Prerequisites

The Jenkins EC2 instance should have the following tools available.

| Tool | Purpose |
|---|---|
| Git | Source checkout |
| Jenkins | CI/CD |
| AWS CLI | AWS operations |
| Terraform | Infrastructure provisioning |
| kubectl | Kubernetes operations |
| Docker | Container build |
| Docker Buildx | BuildKit |
| Trivy | Image security scanning |
| Python 3 | Unit tests and reporting |
| pip / venv | Python dependencies |

The versions used during development included:

```text
Terraform       1.16.5
AWS Provider    6.67.0
Kubernetes      1.36
Python 3.x
Docker BuildKit
Trivy
```

---

# AWS IAM Requirements

The recommended authentication model is:

```text
Jenkins EC2
     |
     v
EC2 Instance Profile / IAM Role
     |
     v
AWS APIs
```

Avoid storing long-lived AWS access keys inside Jenkins whenever possible.

The Jenkins EC2 instance requires permissions appropriate for the actions it performs, including:

- EKS
- ECR
- CloudWatch
- AWS Load Balancer-related operations where applicable
- Terraform-managed infrastructure
- STS identity operations

Kubernetes access is separate from general AWS API authorization and must also be configured through EKS access/RBAC.

The repository contains:

```text
iam_policy.json
```

for project IAM configuration.

Review and scope IAM permissions according to your own AWS environment before using them in production.

---

# Terraform Configuration

Move into the Terraform directory:

```bash
cd /home/ubuntu/zero-downtime-k8s/terraform
```

Initialize Terraform:

```bash
terraform init
```

Validate:

```bash
terraform validate
```

Format:

```bash
terraform fmt -recursive
```

Create a plan:

```bash
terraform plan
```

---

# Terraform Variables

The project includes an email variable for CloudWatch notifications:

```hcl
variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  sensitive   = true
}
```

Create a local:

```text
terraform.tfvars
```

For example:

```hcl
project_name = "zero-downtime"
cluster_name = "zero-downtime-eks"
aws_region   = "ap-south-1"

alert_email = "your-email@example.com"
```

Do **not** commit this file if it contains your personal email address or other environment-specific secrets.

---

# Deploy Infrastructure

From:

```bash
cd /home/ubuntu/zero-downtime-k8s/terraform
```

Run:

```bash
terraform init
```

Then:

```bash
terraform validate
```

Then:

```bash
terraform plan
```

If the plan is correct:

```bash
terraform apply
```

Confirm with:

```text
yes
```

---

# Configure AWS CLI

Set the AWS region:

```bash
export AWS_REGION=ap-south-1
```

Verify the AWS identity:

```bash
aws sts get-caller-identity
```

Retrieve the AWS account ID dynamically:

```bash
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

Set the ECR repository:

```bash
export ECR_REPOSITORY=zero-downtime-app
```

Set the registry:

```bash
export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

Verify:

```bash
echo "${AWS_ACCOUNT_ID}"
echo "${ECR_REGISTRY}"
```

---

# Configure kubectl

Update kubeconfig:

```bash
aws eks update-kubeconfig \
  --region ap-south-1 \
  --name zero-downtime-eks
```

Verify:

```bash
kubectl get nodes
```

---

# Install / Verify AWS Load Balancer Controller

The AWS Load Balancer Controller is required for the Kubernetes Ingress to create/manage the AWS Application Load Balancer.

The controller must be installed and granted the appropriate IAM permissions.

Verify that it is running:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

For a new environment, follow the AWS EKS Load Balancer Controller installation procedure appropriate to your EKS version and IAM model.

The controller installation is not represented as a dedicated Terraform module in this repository, so its exact IAM/Helm configuration may need to be recreated separately when building the project in another AWS account.

---

# Deploy Kubernetes Application

Create the namespace:

```bash
kubectl create namespace zero-downtime
```

Apply the service:

```bash
kubectl apply \
  -f k8s/service.yaml \
  -n zero-downtime
```

Apply the deployment:

```bash
kubectl apply \
  -f k8s/deployment.yaml \
  -n zero-downtime
```

Apply the PodDisruptionBudget:

```bash
kubectl apply \
  -f k8s/pdb.yaml \
  -n zero-downtime
```

Apply the Ingress:

```bash
kubectl apply \
  -f k8s/ingress.yaml \
  -n zero-downtime
```

Check:

```bash
kubectl get pods -n zero-downtime
```

Check deployment:

```bash
kubectl get deployment -n zero-downtime
```

Check service:

```bash
kubectl get service -n zero-downtime
```

Check ingress:

```bash
kubectl get ingress -n zero-downtime
```

---

# Retrieve ALB Hostname

The ALB hostname should not be hard-coded.

Retrieve it dynamically:

```bash
export ALB_HOST=$(kubectl get ingress \
  -n zero-downtime \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

Verify:

```bash
echo "${ALB_HOST}"
```

Test the application:

```bash
curl "http://${ALB_HOST}/"
```

Health check:

```bash
curl "http://${ALB_HOST}/health"
```

Expected:

```text
OK
```

Readiness:

```bash
curl "http://${ALB_HOST}/ready"
```

Expected:

```text
READY
```

---

# Configure Jenkins

Create a Jenkins Pipeline job:

```text
zero-downtime-k8s
```

The pipeline should point to the GitHub repository:

```text
https://github.com/rahulsharma-rks/zero-downtime-k8s
```

The repository contains:

```text
Jenkinsfile
```

The Jenkins server must have access to:

```text
GitHub
AWS
ECR
EKS
Kubernetes
Docker
Trivy
Terraform
```

The Jenkins EC2 IAM role should be used for AWS authentication where possible.

---

# Jenkins Pipeline

The Jenkins pipeline contains the following major stages:

```text
Checkout
    ↓
Setup Python Environment
    ↓
Unit Tests
    ↓
Docker Build
    ↓
Trivy Scan
    ↓
ECR Login
    ↓
Push Image
    ↓
ECR Scan Verification
    ↓
Capture Previous Image
    ↓
Deploy
    ↓
Verify Deployment
    ↓
Rollback if Required
```

---

# Unit Testing

Jenkins runs:

```bash
.venv/bin/python -m unittest discover \
  -s app \
  -p 'test_*.py' \
  -v
```

The application has tests for:

```text
/
 /health
 /ready
```

---

# Docker Build

The pipeline uses BuildKit/buildx:

```bash
docker buildx build \
  --build-arg APP_VERSION="${BUILD_NUMBER}" \
  --tag "${IMAGE_NAME}" \
  --provenance=false \
  --load \
  app/
```

The Jenkins build number becomes the application image tag.

For example:

```text
Build #38
```

produces:

```text
:38
```

---

# Trivy Security Scan

Trivy is the blocking security gate.

The pipeline scans:

```bash
trivy image \
  --scanners vuln \
  --severity HIGH,CRITICAL \
  --ignore-unfixed \
  --exit-code 1 \
  --no-progress \
  "${IMAGE_NAME}"
```

The policy is:

```text
HIGH     → build failure
CRITICAL → build failure
```

if the vulnerability is applicable under the configured scan policy.

---

# ECR Vulnerability Scan

After pushing the image to ECR, Jenkins waits for ECR scan results.

ECR scanning is asynchronous.

The pipeline therefore polls:

```bash
aws ecr describe-image-scan-findings
```

until scan results become available.

The pipeline prints:

```text
ECR SECURITY SCAN SUMMARY

HIGH
CRITICAL
```

It also reports the relevant vulnerability information.

ECR scanning is currently:

```text
Report-only
```

while Trivy remains the blocking gate.

---

# Kubernetes Deployment

The pipeline deploys a new image using the Kubernetes Deployment.

The application container name is:

```text
app
```

A deployment can be performed manually with:

```bash
kubectl set image deployment/zero-downtime-app \
  app="${ECR_REGISTRY}/${ECR_REPOSITORY}:NEW_TAG" \
  -n zero-downtime
```

Then monitor:

```bash
kubectl rollout status \
  deployment/zero-downtime-app \
  -n zero-downtime
```

---

# Rollback

Manual rollback:

```bash
kubectl rollout undo \
  deployment/zero-downtime-app \
  -n zero-downtime
```

Monitor:

```bash
kubectl rollout status \
  deployment/zero-downtime-app \
  -n zero-downtime
```

The Jenkins pipeline performs deterministic rollback when the new version fails its deployment verification.

---

# Monitoring and Alerting

The project integrates:

```text
Amazon CloudWatch
CloudWatch Container Insights
CloudWatch Alarms
Amazon SNS
```

Container Insights provides Kubernetes workload metrics.

The project monitors:

```text
Pod CPU
Pod Memory
Container Restarts
ALB Target 5xx
```

---

# CloudWatch Log Groups

The project configures retention for Container Insights log groups.

Examples:

```text
/aws/containerinsights/zero-downtime-eks/application
/aws/containerinsights/zero-downtime-eks/dataplane
/aws/containerinsights/zero-downtime-eks/host
/aws/containerinsights/zero-downtime-eks/performance
```

Retention:

```text
14 days
```

---

# CloudWatch Alarms

The Terraform configuration includes alarms for:

## High CPU

Threshold:

```text
80%
```

for three consecutive one-minute periods.

## High Memory

Threshold:

```text
80%
```

for three consecutive one-minute periods.

## Container Restart

Alarm when the application container restart metric reaches:

```text
>= 1
```

## ALB Target 5xx

Alarm when the ALB target returns:

```text
>= 1 HTTP 5xx
```

during the evaluation period.

---

# SNS Notifications

CloudWatch alarms publish to an SNS topic:

```text
zero-downtime-cloudwatch-alerts
```

An email subscription is configured through Terraform.

The recipient must confirm the SNS subscription email before notifications are delivered.

---

# Environment-Specific CloudWatch Configuration

The ALB and Target Group dimensions in:

```text
terraform/cloudwatch_alarms.tf
```

contain environment-specific identifiers.

These identifiers are generated by the AWS Load Balancer Controller and therefore differ between environments.

When reproducing the project in another AWS account or cluster, update those dimensions after the ALB and target group are created.

Retrieve load balancer information with:

```bash
aws elbv2 describe-load-balancers \
  --region ap-south-1
```

Retrieve target groups with:

```bash
aws elbv2 describe-target-groups \
  --region ap-south-1
```

Do not assume identifiers from the original environment will be reused.

---

# Useful Kubernetes Commands

## Get all resources

```bash
kubectl get all -n zero-downtime
```

## Get pods

```bash
kubectl get pods -n zero-downtime -o wide
```

## Watch pods

```bash
kubectl get pods \
  -n zero-downtime \
  -w
```

## Deployment

```bash
kubectl get deployment \
  zero-downtime-app \
  -n zero-downtime
```

## Rollout history

```bash
kubectl rollout history \
  deployment/zero-downtime-app \
  -n zero-downtime
```

## Rollout status

```bash
kubectl rollout status \
  deployment/zero-downtime-app \
  -n zero-downtime
```

## Pod logs

```bash
kubectl logs \
  -n zero-downtime \
  deployment/zero-downtime-app
```

## Previous container logs

For CrashLoopBackOff troubleshooting:

```bash
kubectl logs \
  -n zero-downtime \
  <pod-name> \
  --previous
```

## Describe pod

```bash
kubectl describe pod \
  -n zero-downtime \
  <pod-name>
```

## Check ingress

```bash
kubectl get ingress \
  -n zero-downtime
```

---

# Useful AWS Commands

## Current AWS identity

```bash
aws sts get-caller-identity
```

## EKS cluster

```bash
aws eks describe-cluster \
  --name zero-downtime-eks \
  --region ap-south-1
```

## EKS nodes

```bash
kubectl get nodes -o wide
```

## ECR repositories

```bash
aws ecr describe-repositories \
  --region ap-south-1
```

## ECR images

```bash
aws ecr describe-images \
  --repository-name zero-downtime-app \
  --region ap-south-1
```

## ECR scan findings

```bash
aws ecr describe-image-scan-findings \
  --repository-name zero-downtime-app \
  --image-id imageTag=38 \
  --region ap-south-1
```

---

# Replication Guide

## Step 1 - Clone Repository

```bash
git clone https://github.com/rahulsharma-rks/zero-downtime-k8s.git
cd zero-downtime-k8s
```

## Step 2 - Configure AWS

```bash
export AWS_REGION=ap-south-1
```

Verify:

```bash
aws sts get-caller-identity
```

## Step 3 - Provision Infrastructure

```bash
cd terraform
```

Create your local:

```text
terraform.tfvars
```

Then:

```bash
terraform init
terraform validate
terraform plan
terraform apply
```

## Step 4 - Configure kubectl

```bash
aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name zero-downtime-eks
```

Verify:

```bash
kubectl get nodes
```

## Step 5 - Verify AWS Load Balancer Controller

```bash
kubectl get pods \
  -n kube-system | grep aws-load-balancer-controller
```

The controller must be operational before applying the Ingress.

## Step 6 - Deploy Kubernetes Resources

```bash
cd ..
```

```bash
kubectl create namespace zero-downtime
```

```bash
kubectl apply -f k8s/service.yaml \
  -n zero-downtime

kubectl apply -f k8s/deployment.yaml \
  -n zero-downtime

kubectl apply -f k8s/pdb.yaml \
  -n zero-downtime

kubectl apply -f k8s/ingress.yaml \
  -n zero-downtime
```

## Step 7 - Verify Application

```bash
kubectl get pods \
  -n zero-downtime \
  -o wide
```

```bash
kubectl get deployment \
  -n zero-downtime
```

```bash
kubectl get ingress \
  -n zero-downtime
```

Retrieve the ALB:

```bash
export ALB_HOST=$(kubectl get ingress \
  -n zero-downtime \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

Test:

```bash
curl "http://${ALB_HOST}/"
curl "http://${ALB_HOST}/health"
curl "http://${ALB_HOST}/ready"
```

## Step 8 - Configure Jenkins

Install the required tools on the Jenkins EC2 instance.

Configure Jenkins to use:

```text
https://github.com/rahulsharma-rks/zero-downtime-k8s
```

Create a Pipeline job:

```text
zero-downtime-k8s
```

Use:

```text
Jenkinsfile
```

## Step 9 - Run Pipeline

The pipeline performs:

```text
Checkout
Test
Build
Trivy Scan
ECR Push
ECR Scan
Deploy
Verify
Rollback if necessary
```

---

# Testing Zero-Downtime Deployment

Deploy a new image:

```bash
kubectl set image deployment/zero-downtime-app \
  app="${ECR_REGISTRY}/${ECR_REPOSITORY}:NEW_TAG" \
  -n zero-downtime
```

Watch:

```bash
kubectl get pods \
  -n zero-downtime \
  -w
```

At the same time, test:

```bash
while true; do
  curl -s -o /dev/null \
    -w "%{http_code}\n" \
    "http://${ALB_HOST}/health"
done
```

During a normal rolling update, the expectation is that healthy replicas continue serving traffic while Kubernetes replaces the old pods.

---

# Testing Automatic Rollback

For a controlled failure test, configure the application environment with:

```text
READINESS_FAIL=true
```

Then deploy the new version.

Expected behavior:

```text
New Pod Created
      ↓
Pod Starts
      ↓
/ready = 503
      ↓
Pod Never Becomes Ready
      ↓
Rollout Fails / Times Out
      ↓
Jenkins Detects Failure
      ↓
Previous Image Restored
      ↓
Rollback Verified
      ↓
ALB Health Check = 200
```

After the test, restore:

```text
READINESS_FAIL=false
```

---

# Terraform Destroy / Environment Cleanup

When the project is no longer required, Terraform can destroy the AWS infrastructure.

This is especially useful for a lab environment to avoid unnecessary AWS charges.

Go to:

```bash
cd /home/ubuntu/zero-downtime-k8s/terraform
```

First inspect the Terraform state:

```bash
terraform state list
```

Create a destroy plan:

```bash
terraform plan -destroy
```

**Review the output carefully.**

If the resources are correct:

```bash
terraform destroy
```

Confirm:

```text
yes
```

## Verify EKS Was Deleted

```bash
aws eks describe-cluster \
  --name zero-downtime-eks \
  --region ap-south-1
```

The expected result is a resource-not-found error.

## Verify ECR Was Deleted

```bash
aws ecr describe-repositories \
  --repository-names zero-downtime-app \
  --region ap-south-1
```

The expected result is a repository-not-found error if Terraform destroyed the repository.

## Verify ALB Was Deleted

```bash
aws elbv2 describe-load-balancers \
  --region ap-south-1 \
  --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-zerodown`)].LoadBalancerName' \
  --output table
```

No matching load balancer should remain after Kubernetes and the AWS Load Balancer Controller have cleaned up the resources.

## Verify CloudWatch Alarms

```bash
aws cloudwatch describe-alarms \
  --alarm-name-prefix "zero-downtime-" \
  --region ap-south-1 \
  --query 'MetricAlarms[].AlarmName' \
  --output table
```

## Verify SNS

```bash
aws sns list-topics \
  --region ap-south-1 \
  --query 'Topics[?contains(TopicArn, `zero-downtime`)].TopicArn' \
  --output table
```

## Verify Terraform State

```bash
terraform state list
```

The state should contain no remaining managed infrastructure resources after a successful destroy.

---

# Important Cleanup Note

`terraform destroy` removes the infrastructure managed by Terraform.

It does **not** delete the GitHub repository.

The following remain in GitHub:

```text
Application source
Terraform code
Kubernetes manifests
Jenkinsfile
Dockerfile
README
Git history
```

This allows the complete environment to be recreated later.

---

# Security Considerations

The project incorporates several security practices.

## IAM

Prefer:

```text
EC2 Instance Profile / IAM Role
```

over static AWS access keys.

## Kubernetes

The application uses:

```text
Non-root user
Read-only root filesystem
Dropped Linux capabilities
No privilege escalation
RuntimeDefault seccomp
Resource limits
Resource requests
```

## Container Image

The image is scanned using:

```text
Trivy
```

and:

```text
Amazon ECR scanning
```

## Vulnerability Management

Vulnerabilities are investigated rather than blindly ignored.

The workflow is:

```text
Finding
  ↓
Affected package
  ↓
Affected base image
  ↓
Exploitability / applicability
  ↓
Remediation
  ↓
Verification
```

## Secrets

Do not commit:

```text
AWS access keys
AWS secret keys
terraform.tfvars
Passwords
Private keys
Jenkins secrets
```

Environment-specific sensitive values should be provided through secure configuration mechanisms.

---

# What This Project Demonstrates

## AWS

```text
VPC
EC2
EKS
ECR
IAM
ALB
NAT Gateway
CloudWatch
SNS
```

## Kubernetes

```text
Deployments
Rolling Updates
Services
Ingress
Readiness Probes
Liveness Probes
Startup Probes
PDB
Topology Spread
Security Context
Resource Requests/Limits
Rollback
```

## DevOps

```text
CI/CD
Infrastructure as Code
Containerization
Automated Testing
Security Scanning
Automated Rollback
Observability
Failure Testing
```

## Terraform

```text
Reusable infrastructure
AWS modules
Resource dependencies
State management
Infrastructure provisioning
Infrastructure destruction
```

## Jenkins

```text
Pipeline as Code
Automated testing
Docker builds
Security gates
ECR integration
Kubernetes deployment
Rollback automation
```

---

# Lessons Learned

## 1. A healthy Pod spec does not mean a healthy application

Kubernetes can successfully create a pod while the application itself is unable to serve traffic.

That is why readiness and liveness probes are critical.

## 2. Readiness is critical for zero-downtime deployments

A new pod should not receive production traffic until it is actually ready.

The `/ready` endpoint provides that signal.

## 3. Previous container logs matter during CrashLoopBackOff

When investigating a restarting container, the previous container instance can contain the most useful logs:

```bash
kubectl logs <pod> --previous
```

## 4. ImagePullBackOff can hide infrastructure problems

A pod specification may be completely correct while image pulls fail because of:

```text
NAT
Networking
Registry access
DNS
IAM
```

## 5. Security scanning is not the end of vulnerability management

A scanner finding needs investigation.

The actual workflow is:

```text
Finding
  ↓
Affected package
  ↓
Affected base image
  ↓
Exploitability / applicability
  ↓
Remediation
  ↓
Verification
```

## 6. ECR scans are asynchronous

Immediately querying ECR after pushing an image can result in scan results not being available yet.

The pipeline therefore polls until results become available.

## 7. Trivy and ECR serve different purposes

In this project:

```text
Trivy
```

is the blocking CI security gate.

While:

```text
ECR
```

provides an additional AWS-native vulnerability report.

## 8. Rollback must be deterministic

Simply executing:

```bash
kubectl rollout undo
```

is not always enough for a CI/CD system that needs explicit verification.

The pipeline captures the previous image and verifies that the expected version is restored.

---

# Known Limitations

This is a production-style learning and portfolio project, not a complete enterprise platform.

Some environment-specific components require additional work for a fully portable production implementation.

## AWS Load Balancer Controller

The controller's IAM/installation configuration is not represented as a dedicated Terraform module in this repository.

It must be installed and configured separately when reproducing the environment.

## CloudWatch ALB Dimensions

The CloudWatch ALB alarms contain environment-specific:

```text
LoadBalancer
TargetGroup
```

dimensions.

These identifiers change when a new ALB is created.

They must therefore be updated for another environment.

## Jenkins

Jenkins is hosted on a standalone Ubuntu EC2 instance.

For a larger production organization, Jenkins itself would require additional:

```text
High availability
Backup
Secret management
Agent management
Access control
Monitoring
Disaster recovery
```

## Single NAT Gateway

The lab architecture uses one NAT Gateway.

A production environment requiring higher availability across Availability Zones would generally consider multiple NAT Gateways and corresponding routing.

## Zero Downtime Is Not Absolute

The Kubernetes configuration is designed to maintain application availability during normal rolling updates.

It does not guarantee zero downtime against every possible failure such as:

```text
Complete AZ failure
Cluster failure
ALB failure
AWS service disruption
Application dependency failure
Database failure
Network partition
Incorrect infrastructure changes
```

---

# Final Result

The final system successfully demonstrated:

```text
Terraform Infrastructure
        ↓
Amazon EKS
        ↓
Kubernetes Application
        ↓
AWS Load Balancer Controller
        ↓
Application Load Balancer
        ↓
Zero-Downtime Rolling Deployment
        ↓
Jenkins CI/CD
        ↓
Automated Rollback
        ↓
Production Hardening
        ↓
Failure Testing
        ↓
Trivy Security Gate
        ↓
ECR Vulnerability Reporting
        ↓
Vulnerability Remediation
        ↓
CloudWatch Monitoring
        ↓
SNS Alerting
```

The final application release was validated with:

```text
3/3 application pods Ready
0 unexpected restarts
ALB health check = HTTP 200
/health = HTTP 200
/ready = HTTP 200
Trivy HIGH/CRITICAL = 0
```

The final verified production image during development was:

```text
Build #38
```

The final security hardening work resulted in the remediation of the investigated zlib vulnerability before deployment.

---

# Repository

GitHub:

https://github.com/rahulsharma-rks/zero-downtime-k8s

The repository contains the complete project source, including:

```text
Terraform
Kubernetes manifests
Jenkins pipeline
Dockerfile
Python application
Unit tests
IAM configuration
CloudWatch configuration
```

---

# Project Summary

This project was built to demonstrate the complete lifecycle of a Kubernetes application on AWS:

```text
PLAN
 ↓
PROVISION
 ↓
BUILD
 ↓
TEST
 ↓
SCAN
 ↓
PUSH
 ↓
DEPLOY
 ↓
VERIFY
 ↓
MONITOR
 ↓
ROLL BACK WHEN REQUIRED
 ↓
HARDEN
 ↓
DESTROY
```

The key objective was not simply to deploy an application to EKS, but to demonstrate how infrastructure, Kubernetes, CI/CD, security, observability, and failure recovery can be combined into a repeatable DevOps workflow.
'''

path = "/mnt/data/README.md"
with open(path, "w", encoding="utf-8") as f:
    f.write(readme)

print(path)
