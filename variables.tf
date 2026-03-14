variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["production", "staging", "dev"], var.environment)
    error_message = "Must be production, staging, or dev."
  }
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "security-iam-demo"
}

variable "owner" {
  description = "Owner tag applied to all resources"
  type        = string
  default     = "security-team"
}

variable "ec2_instance_type" {
  description = "EC2 instance type for the app server"
  type        = string
  default     = "t3.micro"
}

variable "ec2_ami" {
  description = "Amazon Linux 2023 AMI — update per region"
  type        = string
  default     = "ami-0c02fb55956c7d316" # Amazon Linux 2023 us-east-1
}

variable "log_retention_days" {
  description = "CloudWatch and CloudTrail log retention in days"
  type        = number
  default     = 90
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH to EC2 — use your IP"
  type        = string
  default     = "0.0.0.0/0" # Restrict to your IP in terraform.tfvars
}
