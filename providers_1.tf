terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  # Uncomment when you have a remote state bucket
  # backend "s3" {
  #   bucket = "your-terraform-state-bucket"
  #   key    = "project-2/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "security-iam-demo"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Pillar      = "Security"
      Owner       = var.owner
    }
  }
}
