variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Project name"
  type        = string
  default     = "zero-downtime"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "zero-downtime-eks"
}
