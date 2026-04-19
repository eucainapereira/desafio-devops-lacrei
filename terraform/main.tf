# Provider padrão: São Paulo (Brasil) - Onde fica nossa Produção
provider "aws" {
  region = "sa-east-1"
}

# Provider Auxiliar: Virgínia (EUA) - Apenas para o App Runner (Staging)
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
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

/* 
# --- AWS App Runner (CONFIGURAÇÃO PARA STAGING) ---
# Se for ativar, lembre-se de usar: provider = aws.virginia
resource "aws_apprunner_service" "app" {
  provider     = aws.virginia
  count        = var.app_runner_count 
  service_name = "app-lacrei-saude"

  source_configuration {
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
}
*/

# --- Variables ---
variable "aws_region" { default = "sa-east-1" }
variable "app_runner_count" { default = 0 }
variable "ecr_repository_url" { type = string }
variable "environment" { default = "production" }
