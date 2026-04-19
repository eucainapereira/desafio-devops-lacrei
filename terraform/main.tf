provider "aws" {
  region = var.aws_region
}

# --- VPC & Networking ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "lacrei-saude-vpc" }
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags       = { Name = "lacrei-public-subnet" }
}

# --- AWS App Runner (Deploy Simples e Robusto) ---
resource "aws_apprunner_service" "app" {
  service_name = "app-lacrei-saude"

  source_configuration {
    image_repository {
      image_identifier      = "${var.ecr_repository_url}:latest"
      image_repository_type = "ECR"
      image_configuration {
        port = "3000"
        runtime_environment_variables = {
          NODE_ENV = "production"
        }
      }
    }
    auto_deployments_enabled = true
  }

  tags = {
    Environment = var.environment
  }
}

# --- Variables ---
variable "aws_region" { default = "sa-east-1" }
variable "environment" { default = "production" }
variable "ecr_repository_url" { type = string }
