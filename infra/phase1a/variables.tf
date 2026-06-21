variable "aws_region" {
  description = "AWS region for Phase 1a resources."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short name used as an AWS resource prefix."
  type        = string
  default     = "event-commerce"
}

variable "environment" {
  description = "Deployment environment name."
  type        = string
  default     = "dev"
}

variable "github_repository" {
  description = "GitHub repository allowed to assume the deploy role, in owner/name form."
  type        = string
  default     = "tirthomahfuz/event-driven-commerce"
}

variable "github_branch" {
  description = "Branch allowed to deploy with GitHub OIDC."
  type        = string
  default     = "main"
}

variable "github_oidc_provider_arn" {
  description = "Existing GitHub Actions OIDC provider ARN. Leave null to create one."
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "CIDR block for the Phase 1a VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "web_cpu" {
  description = "Fargate CPU units for the Next.js task."
  type        = number
  default     = 256
}

variable "web_memory" {
  description = "Fargate memory in MiB for the Next.js task."
  type        = number
  default     = 512
}

variable "orders_cpu" {
  description = "Fargate CPU units for the FastAPI task."
  type        = number
  default     = 256
}

variable "orders_memory" {
  description = "Fargate memory in MiB for the FastAPI task."
  type        = number
  default     = 512
}
