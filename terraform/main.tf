# Provider para a Virgínia (Padrão para App Runner e Staging)
provider "aws" {
  region = "us-east-1"
}

# Provider para São Paulo (Padrão para a Produção na EC2)
provider "aws" {
  alias  = "sa-east-1"
  region = "sa-east-1"
}

# --- VPC & Networking (Forçado para São Paulo) ---
resource "aws_vpc" "main" {
  provider             = aws.sa-east-1
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "lacrei-saude-vpc" }
}

resource "aws_subnet" "public" {
  provider   = aws.sa-east-1
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
  tags       = { Name = "lacrei-public-subnet" }
}

# --- AWS App Runner (CONFIGURAÇÃO PARA STAGING - us-east-1) ---
# Count configurado como 0 para evitar erros de assinatura em contas Free Tier.
# Este bloco usa o provider padrão (us-east-1).
resource "aws_apprunner_service" "app" {
  count        = var.app_runner_count 
  service_name = "app-lacrei-saude"

  source_configuration {
    authentication_configuration {
      # Role para o App Runner puxar imagens do ECR
      access_role_arn = "arn:aws:iam::873011686071:role/apprunner-service-role-lacrei"
    }
    image_repository {
      image_identifier      = "873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude:latest"
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
    Environment = "staging"
  }
}

# --- Variables ---
variable "aws_region" { default = "sa-east-1" }
variable "app_runner_count" { default = 0 }
variable "ecr_repository_url" { type = string }
variable "environment" { default = "production" }
