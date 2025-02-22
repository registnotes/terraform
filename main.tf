# ------------------------------
# Terraform configuration
# ------------------------------

terraform {
  required_version = ">=0.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~>3.0"
    }
  }

  # backend "s3" {
  #   bucket = "laravel-app-tfstate-bucket-11111"
  #   key = "laravel-app-dev-.tfstate"
  #   region = "ap-northeast-1"
  #   profile = "terraform"
  # }
  backend "local" {
    path = "./terraform.tfstate"
  }
}

# ------------------------------
# Provider
# ------------------------------
provider "aws" {
  profile = "terraform"
  region  = "ap-northeast-1"
}

provider "aws" {
  alias   = "virginia"
  profile = "terraform"
  region  = "us-east-1"
}
# ------------------------------
# Variables
# ------------------------------
variable "project" {
  type = string
}

variable "environment" {
  type = string
}

variable "domain" {
  type = string
}

variable "s3_bucket_name" {
  type = string
}

variable "github_pat_token" {
  type      = string
  sensitive = true
}