# Provider padrão: São Paulo (Brasil) - Onde fica nossa Produção
provider "aws" {
  region = "sa-east-1"
}

# Provider Auxiliar: Virgínia (EUA) - Apenas para o App Runner (Staging)
provider "aws" {
  alias  = "virginia"
  region = "us-east-1"
}

# --- VPC & Networking (São Paulo) ---
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = { Name = "lacrei-saude-vpc" }
}

# Criar o Internet Gateway (Portão da Internet)
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "lacrei-igw" }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags                    = { Name = "lacrei-public-subnet" }
}

# Criar a Tabela de Rotas para apontar para o Internet Gateway
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "lacrei-public-rt" }
}

# Associar a Subnet com a Tabela de Rotas
resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

/* 
# --- AWS App Runner (CONFIGURAÇÃO PARA STAGING) ---
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
