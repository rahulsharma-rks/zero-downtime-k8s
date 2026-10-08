# Zero-Downtime Kubernetes Deployment with Jenkins on AWS EKS

A production-style DevOps project demonstrating Infrastructure as Code, CI/CD automation, zero-downtime rolling deployments, deterministic rollback, Kubernetes hardening, container security, vulnerability remediation, and observability on Amazon EKS.

## Project Overview

The platform uses Terraform to provision AWS infrastructure and Jenkins on a standalone Ubuntu EC2 instance for both infrastructure operations and CI/CD.

Core flow:

```text
GitHub
  |
  v
Jenkins (Ubuntu EC2)
  |
  +--> Terraform --> AWS Infrastructure
  |
  +--> Tests --> Docker BuildKit --> Trivy --> ECR
                                      |
                                      v
                              ECR Scan Verification
                                      |
                                      v
                                  Amazon EKS
                                      |
                         Kubernetes Rolling Update
                                      |
                           +----------+----------+
                           |                     |
                        Healthy                Failed
                           |                     |
                           v                     v
                        Continue              Rollback
```

Application traffic:

```text
Internet
   |
   v
AWS Application Load Balancer
   |
   v
ALB Target Group (IP targets)
   |
   v
EKS Pod IPs
   |
   v
Application Container
```

Kubernetes Ingress is watched by the AWS Load Balancer Controller, which configures the ALB and target group.

## Goals

- Provision AWS infrastructure with Terraform.
- Deploy an application to Amazon EKS.
- Expose it through AWS ALB.
- Implement Kubernetes rolling deployments.
- Maintain application availability during normal rolling updates.
- Automate CI/CD using Jenkins.
- Automatically roll back failed deployments.
- Harden the Kubernetes workload.
- Scan container images with Trivy and ECR.
- Investigate and remediate a real vulnerability.
- Monitor workloads with CloudWatch Container Insights.
- Alert through CloudWatch and SNS.
- Destroy the environment cleanly with Terraform.

## Technology Stack

| Component | Technology |
|---|---|
| Cloud | AWS |
| Region | `ap-south-1` |
| IaC | Terraform |
| Kubernetes | Amazon EKS 1.36 |
| CI/CD | Jenkins |
| Jenkins Host | Standalone Ubuntu EC2 |
| Registry | Amazon ECR |
| Build | Docker BuildKit / buildx |
| Security | Trivy + ECR scanning |
| Load Balancer | AWS Application Load Balancer |
| ALB Integration | AWS Load Balancer Controller |
| Monitoring | CloudWatch Container Insights |
| Alerting | Amazon SNS |
| Application | Python Flask |
| Application Port | 8080 |

## AWS Design

VPC:

```text
CIDR: 10.20.0.0/16
```

Private subnets:

```text
10.20.1.0/24
10.20.2.0/24
```

Public subnets:

```text
10.20.101.0/24
10.20.102.0/24
```

One NAT Gateway is used for private-subnet egress.

EKS:

```text
Cluster: zero-downtime-eks
Kubernetes: 1.36
```

Managed node group:

```text
Instance: t3.small
Desired: 3
Minimum: 2
Maximum: 3
Disk: 20 GB
Capacity: ON_DEMAND
```

EKS add-ons:

```text
coredns
kube-proxy
vpc-cni
eks-pod-identity-agent
amazon-cloudwatch-observability
```

## Repository Structure

```text
zero-downtime-k8s/
├── .gitignore
├── Jenkinsfile
├── iam_policy.json
├── app/
│   ├── Dockerfile
│   ├── app.py
│   ├── requirements.txt
│   └── test_app.py
├── k8s/
│   ├── deployment.yaml
│   ├── ingress.yaml
│   ├── pdb.yaml
│   └── service.yaml
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

# Project Phases

Exactly 10 phases were implemented:

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

## Phase 1 - Infrastructure

Terraform provisions the AWS foundation:

- VPC
- Public and private subnets
- Internet Gateway
- NAT Gateway
- Routing
- IAM
- ECR
- EKS prerequisites

Versions used:

```text
Terraform: 1.16.5
AWS Provider: 6.67.0
VPC Module: 6.7.3
EKS Module: 21.26.0
```

## Phase 2 - Amazon EKS

The EKS cluster uses Kubernetes 1.36 and a managed node group with three `t3.small` workers.

The final node-group configuration is:

```text
min_size     = 2
max_size     = 3
desired_size = 3
```

## Phase 3 - Kubernetes Application

The Flask application exposes:

```text
/
/health
/ready
```

`/health` returns HTTP 200 when the application is running.

`/ready` returns HTTP 200 when the application is ready to receive traffic.

Readiness can deliberately be failed with:

```text
READINESS_FAIL=true
```

This is used for rollback testing.

## Phase 4 - ALB / Networking

Kubernetes Ingress is integrated with the AWS Load Balancer Controller.

The ALB uses:

```text
Target Type: IP
Health Check: /health
Success Code: 200
```

The physical request path is:

```text
Internet
  |
  v
ALB
  |
  v
Target Group
  |
  v
Pod IP
```

The controller path is:

```text
Kubernetes Ingress
  |
  v
AWS Load Balancer Controller
  |
  v
AWS ALB / Target Group
```

## Phase 5 - Zero-Downtime Rolling Deployment

The Deployment uses:

```yaml
replicas: 3

strategy:
  type: RollingUpdate
  rollingUpdate:
    maxUnavailable: 0
    maxSurge: 1
```

A new pod is created before an old pod is removed, and readiness must succeed before the new pod participates in traffic.

This is a zero-downtime strategy under normal rolling-update conditions, not an absolute guarantee against every infrastructure or application failure.

Additional controls include readiness, liveness and startup probes, a 30-second termination grace period, a 10-second preStop hook, a PodDisruptionBudget, and topology spreading.

## Phase 6 - Jenkins CI/CD

Jenkins runs outside EKS on a standalone Ubuntu EC2 instance.

It performs both:

1. Terraform infrastructure operations.
2. Application CI/CD.

Pipeline:

```text
Checkout
  ↓
Python Environment
  ↓
Unit Tests
  ↓
Docker BuildKit
  ↓
Trivy
  ↓
ECR Login
  ↓
Push
  ↓
ECR Scan Verification
  ↓
Capture Previous Image
  ↓
Deploy
  ↓
Verify
  ↓
Rollback if Required
```

## Phase 7 - Automated Rollback

Before deployment, Jenkins captures the currently running image.

If the new version fails rollout or validation, Jenkins restores the previous image and verifies:

```text
Deployment Ready
Image Restored
ALB Health = 200
```

The application container name is:

```text
app
```

Example:

```bash
kubectl set image deployment/zero-downtime-app   app="${ECR_REGISTRY}/${ECR_REPOSITORY}:${PREVIOUS_TAG}"   -n zero-downtime
```

## Phase 8 - Production Hardening

The workload uses:

```text
Resource requests and limits
Readiness probe
Liveness probe
Startup probe
PodDisruptionBudget
Topology spread
Non-root user
Read-only root filesystem
Dropped capabilities
No privilege escalation
RuntimeDefault seccomp
Graceful termination
```

Security context includes:

```text
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities.drop: ALL
```

A writable `emptyDir` is mounted at `/tmp`.

## Phase 9 - Failure / Rollback Testing

The application can intentionally fail readiness:

```text
READINESS_FAIL=true
```

This makes `/ready` return HTTP 503.

The tested failure path is:

```text
New Version
   ↓
Readiness Failure
   ↓
Rollout Failure / Timeout
   ↓
Jenkins Detects Failure
   ↓
Automatic Rollback
   ↓
Previous Version Restored
   ↓
Deployment Verified
   ↓
ALB Health = 200
```

## Phase 10 - Security & CI/CD Hardening

Phase 10 was the final phase and contains three subphases.

### 10.1 BuildKit + ECR Scan Integration

The pipeline builds with BuildKit:

```bash
docker buildx build   --build-arg APP_VERSION="${BUILD_NUMBER}"   --tag "${IMAGE_NAME}"   --provenance=false   --load   app/
```

### 10.2 ECR Vulnerability Reporting

ECR scan results are asynchronous, so Jenkins polls for availability.

ECR reports:

```text
HIGH
CRITICAL
```

The policy is:

```text
Trivy = blocking security gate
ECR   = report-only
```

### 10.3 Vulnerability Investigation and Remediation

ECR identified:

```text
CVE-2026-85091
```

in the Debian-based `python:3.12-slim` image through its zlib dependency.

The investigation evaluated `python:3.12-alpine` and upgraded zlib:

```dockerfile
RUN apk update &&     apk upgrade zlib &&     rm -rf /var/cache/apk/*
```

The final image was validated with unit tests, Trivy, container execution, health/readiness checks, non-root execution and read-only filesystem testing.

Final blocking scan result:

```text
HIGH     = 0
CRITICAL = 0
```

The final verified production release during development was Build #38.

# Final Dockerfile

```dockerfile
FROM python:3.12-alpine

ARG APP_VERSION=dev

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV APP_VERSION=${APP_VERSION}

RUN apk update &&     apk upgrade zlib &&     rm -rf /var/cache/apk/*

WORKDIR /app

COPY requirements.txt .

RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

RUN addgroup -S appgroup &&     adduser -S -D -H -s /sbin/nologin -G appgroup appuser

USER appuser

EXPOSE 8080

CMD ["python", "app.py"]
```

# Jenkins EC2 Setup

Jenkins is hosted on a separate Ubuntu EC2 instance:

```text
Ubuntu EC2
  |
  +-- Jenkins
  +-- Git
  +-- Docker / BuildKit
  +-- AWS CLI
  +-- kubectl
  +-- Terraform
  +-- Trivy
  +-- Python
```

Jenkins is not deployed inside EKS.

# Prerequisites

Required tooling:

| Tool | Purpose |
|---|---|
| Git | Source control |
| Jenkins | CI/CD |
| AWS CLI | AWS operations |
| Terraform | Infrastructure |
| kubectl | Kubernetes |
| Docker | Container build |
| Docker Buildx | BuildKit |
| Trivy | Security scanning |
| Python 3 | Tests/reporting |

Versions used during development:

```text
Terraform: 1.16.5
AWS Provider: 6.67.0
Kubernetes: 1.36
```

# AWS IAM Requirements

The preferred authentication model is:

```text
Jenkins EC2
  |
  v
EC2 Instance Profile / IAM Role
  |
  v
AWS APIs
```

Avoid long-lived AWS access keys where possible.

Jenkins requires appropriate permissions for the AWS and EKS operations performed by Terraform and the CI/CD pipeline.

Kubernetes authorization is separately configured through EKS access/RBAC.

The repository contains `iam_policy.json`; review and least-privilege the permissions for your environment before production use.

# Terraform Configuration

```bash
cd /home/ubuntu/zero-downtime-k8s/terraform

terraform init
terraform validate
terraform fmt -recursive
terraform plan
```

Create a local `terraform.tfvars` if required:

```hcl
project_name = "zero-downtime"
cluster_name = "zero-downtime-eks"
aws_region   = "ap-south-1"

alert_email = "your-email@example.com"
```

Do not commit environment-specific secrets or personal configuration.

# Deploy Infrastructure

```bash
cd /home/ubuntu/zero-downtime-k8s/terraform

terraform init
terraform validate
terraform plan
terraform apply
```

Review the plan before confirming `yes`.

# Configure AWS CLI

```bash
export AWS_REGION=ap-south-1

aws sts get-caller-identity

export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

export ECR_REPOSITORY=zero-downtime-app

export ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
```

# Configure kubectl

```bash
aws eks update-kubeconfig   --region ap-south-1   --name zero-downtime-eks

kubectl get nodes
```

# AWS Load Balancer Controller

The AWS Load Balancer Controller is required for the Kubernetes Ingress to manage the AWS ALB.

Verify it:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

The controller installation and IAM configuration are not represented as a dedicated Terraform module in this repository. When reproducing the environment, install it according to the AWS EKS Load Balancer Controller procedure appropriate to the target cluster and IAM model.

# Deploy Kubernetes Application

```bash
kubectl create namespace zero-downtime

kubectl apply -f k8s/service.yaml   -n zero-downtime

kubectl apply -f k8s/deployment.yaml   -n zero-downtime

kubectl apply -f k8s/pdb.yaml   -n zero-downtime

kubectl apply -f k8s/ingress.yaml   -n zero-downtime
```

Verify:

```bash
kubectl get pods -n zero-downtime
kubectl get deployment -n zero-downtime
kubectl get service -n zero-downtime
kubectl get ingress -n zero-downtime
```

# Retrieve ALB Hostname

Do not hard-code the ALB hostname.

```bash
export ALB_HOST=$(kubectl get ingress   -n zero-downtime   -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

echo "${ALB_HOST}"
```

Test:

```bash
curl "http://${ALB_HOST}/"
curl "http://${ALB_HOST}/health"
curl "http://${ALB_HOST}/ready"
```

# Configure Jenkins

Create a Jenkins Pipeline job:

```text
zero-downtime-k8s
```

Repository:

```text
https://github.com/rahulsharma-rks/zero-downtime-k8s
```

Use the repository's `Jenkinsfile`.

Jenkins requires access to:

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

Use the Jenkins EC2 IAM role for AWS authentication where possible.

# Jenkins Pipeline

Major stages:

```text
Checkout
Setup Python Environment
Unit Tests
Docker Build
Trivy Scan
ECR Login
Push Image
ECR Scan Verification
Capture Previous Image
Deploy
Verify Deployment
Rollback if Required
```

Unit tests:

```bash
.venv/bin/python -m unittest discover   -s app   -p 'test_*.py'   -v
```

Docker build:

```bash
docker buildx build   --build-arg APP_VERSION="${BUILD_NUMBER}"   --tag "${IMAGE_NAME}"   --provenance=false   --load   app/
```

Trivy:

```bash
trivy image   --scanners vuln   --severity HIGH,CRITICAL   --ignore-unfixed   --exit-code 1   --no-progress   "${IMAGE_NAME}"
```

# Useful Kubernetes Commands

```bash
kubectl get all -n zero-downtime

kubectl get pods -n zero-downtime -o wide

kubectl get pods -n zero-downtime -w

kubectl get deployment zero-downtime-app -n zero-downtime

kubectl rollout status deployment/zero-downtime-app -n zero-downtime

kubectl rollout history deployment/zero-downtime-app -n zero-downtime

kubectl logs -n zero-downtime deployment/zero-downtime-app

kubectl logs -n zero-downtime <pod-name> --previous

kubectl describe pod -n zero-downtime <pod-name>

kubectl get ingress -n zero-downtime
```

# Useful AWS Commands

```bash
aws sts get-caller-identity

aws eks describe-cluster   --name zero-downtime-eks   --region ap-south-1

aws ecr describe-repositories   --region ap-south-1

aws ecr describe-images   --repository-name zero-downtime-app   --region ap-south-1

aws elbv2 describe-load-balancers   --region ap-south-1

aws elbv2 describe-target-groups   --region ap-south-1
```

# CloudWatch Monitoring

The project uses:

```text
CloudWatch Container Insights
CloudWatch Logs
CloudWatch Alarms
SNS
```

Monitored signals include:

```text
Pod CPU utilization
Pod memory utilization
Container restarts
ALB target HTTP 5xx
```

Container Insights log groups use 14-day retention.

CloudWatch alarm notifications are sent through an SNS topic. The email recipient must confirm the SNS subscription.

## Environment-specific ALB dimensions

`terraform/cloudwatch_alarms.tf` contains ALB and target-group dimensions generated for the current environment.

For a new environment, retrieve the new values:

```bash
aws elbv2 describe-load-balancers --region ap-south-1
aws elbv2 describe-target-groups --region ap-south-1
```

Then update the Terraform alarm dimensions accordingly.

# Replication Guide

Clone:

```bash
git clone https://github.com/rahulsharma-rks/zero-downtime-k8s.git
cd zero-downtime-k8s
```

Configure AWS:

```bash
export AWS_REGION=ap-south-1
aws sts get-caller-identity
```

Provision infrastructure:

```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

Configure kubectl:

```bash
aws eks update-kubeconfig   --region "${AWS_REGION}"   --name zero-downtime-eks
```

Verify nodes:

```bash
kubectl get nodes
```

Verify the AWS Load Balancer Controller:

```bash
kubectl get pods -n kube-system | grep aws-load-balancer-controller
```

Deploy the application:

```bash
cd ..

kubectl create namespace zero-downtime

kubectl apply -f k8s/service.yaml -n zero-downtime
kubectl apply -f k8s/deployment.yaml -n zero-downtime
kubectl apply -f k8s/pdb.yaml -n zero-downtime
kubectl apply -f k8s/ingress.yaml -n zero-downtime
```

Verify:

```bash
kubectl get pods -n zero-downtime -o wide
kubectl get deployment -n zero-downtime
kubectl get ingress -n zero-downtime
```

Retrieve and test the ALB:

```bash
export ALB_HOST=$(kubectl get ingress   -n zero-downtime   -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

curl "http://${ALB_HOST}/health"
curl "http://${ALB_HOST}/ready"
```

Configure Jenkins against the repository and run the pipeline.

# Testing Zero-Downtime Deployment

Deploy a new image:

```bash
kubectl set image deployment/zero-downtime-app   app="${ECR_REGISTRY}/${ECR_REPOSITORY}:NEW_TAG"   -n zero-downtime
```

Watch pods:

```bash
kubectl get pods -n zero-downtime -w
```

Continuously test the ALB:

```bash
while true; do
  curl -s -o /dev/null     -w "%{http_code}
"     "http://${ALB_HOST}/health"
done
```

Under normal rolling-update conditions, healthy replicas should continue serving while old pods are replaced.

# Testing Automatic Rollback

Use the application's readiness failure mechanism for a controlled test:

```text
READINESS_FAIL=true
```

Expected flow:

```text
New Pod
  ↓
/ready = 503
  ↓
Rollout cannot complete
  ↓
Jenkins detects failure
  ↓
Previous image restored
  ↓
Rollback verified
  ↓
ALB = 200
```

Restore the healthy configuration after testing:

```text
READINESS_FAIL=false
```

# Terraform Destroy / Environment Cleanup

For a lab environment, destroy the AWS infrastructure when finished to avoid unnecessary charges.

Go to:

```bash
cd /home/ubuntu/zero-downtime-k8s/terraform
```

Inspect state:

```bash
terraform state list
```

Create the destroy plan:

```bash
terraform plan -destroy
```

Review it carefully.

Destroy:

```bash
terraform destroy
```

Confirm:

```text
yes
```

Verify EKS:

```bash
aws eks describe-cluster   --name zero-downtime-eks   --region ap-south-1
```

Verify ECR:

```bash
aws ecr describe-repositories   --repository-names zero-downtime-app   --region ap-south-1
```

Verify ALB:

```bash
aws elbv2 describe-load-balancers   --region ap-south-1   --query 'LoadBalancers[?contains(LoadBalancerName, `k8s-zerodown`)].LoadBalancerName'   --output table
```

Verify CloudWatch alarms:

```bash
aws cloudwatch describe-alarms   --alarm-name-prefix "zero-downtime-"   --region ap-south-1   --query 'MetricAlarms[].AlarmName'   --output table
```

Verify SNS:

```bash
aws sns list-topics   --region ap-south-1   --query 'Topics[?contains(TopicArn, `zero-downtime`)].TopicArn'   --output table
```

Finally:

```bash
terraform state list
```

A successful destroy should leave no Terraform-managed infrastructure resources.

`terraform destroy` does not delete the GitHub repository, source code, Terraform files, Kubernetes manifests, Jenkinsfile, or Git history.

# Security Considerations

The project uses:

```text
EC2 IAM role instead of long-lived AWS credentials
Non-root container
Read-only root filesystem
Dropped Linux capabilities
No privilege escalation
RuntimeDefault seccomp
Resource requests and limits
Trivy scanning
ECR vulnerability reporting
```

Do not commit:

```text
AWS credentials
Private keys
Passwords
Jenkins secrets
terraform.tfvars containing sensitive data
```

Use least-privilege IAM for production deployments.

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
Infrastructure provisioning
AWS modules
Resource dependencies
State management
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

# Lessons Learned

### Healthy Kubernetes resources do not necessarily mean a healthy application

Readiness and liveness checks provide application-level health signals.

### Readiness is critical for safe rolling deployments

A pod should become a traffic target only after it is ready.

### Previous logs are important for CrashLoopBackOff

```bash
kubectl logs <pod> --previous
```

can reveal failures from the previous container instance.

### ImagePullBackOff can be an infrastructure problem

A valid Pod spec can still fail to pull an image because of NAT, networking, DNS, registry access, or IAM.

### Vulnerability findings require investigation

The workflow should be:

```text
Detect
  ↓
Investigate
  ↓
Identify package/base image
  ↓
Remediate
  ↓
Rebuild
  ↓
Rescan
  ↓
Deploy
```

### ECR scanning is asynchronous

The pipeline must wait for scan results rather than assuming they are immediately available.

### Security tools can have different roles

Trivy is the blocking gate in this project, while ECR provides an additional AWS-native report.

### Rollback should be explicitly verified

A CI/CD system should verify that the expected previous image is restored and that the application is healthy after rollback.

# Known Limitations

This is a production-style learning and portfolio project, not a complete enterprise platform.

## AWS Load Balancer Controller

The controller's IAM/installation configuration is not represented as a dedicated Terraform module in this repository and must be recreated for a new environment.

## CloudWatch ALB Dimensions

ALB and target-group identifiers are environment-specific and must be updated when recreating the environment.

## Jenkins

Jenkins runs on one standalone Ubuntu EC2 instance. Enterprise use would require additional high availability, backup, secret management, agent management, access control, monitoring, and disaster recovery.

## NAT Gateway

The lab uses one NAT Gateway. Production environments requiring stronger AZ-level resilience may use one NAT Gateway per Availability Zone.

## Zero Downtime Is Not Absolute

The rolling strategy is designed for availability during normal application updates. It does not guarantee zero downtime against every possible AWS, AZ, cluster, ALB, dependency, database, or network failure.

# Final Result

The final system demonstrated:

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

Final validation during development included:

```text
3/3 application pods Ready
0 unexpected restarts
ALB health check = HTTP 200
/health = HTTP 200
/ready = HTTP 200
Trivy HIGH/CRITICAL = 0
```

# Repository

GitHub:

https://github.com/rahulsharma-rks/zero-downtime-k8s

The repository contains:

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

# Project Summary

The project demonstrates the complete lifecycle of a Kubernetes application on AWS:

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

The objective was not simply to deploy an application to EKS, but to demonstrate how infrastructure, Kubernetes, CI/CD, security, observability, and failure recovery can be combined into a repeatable DevOps workflow.
