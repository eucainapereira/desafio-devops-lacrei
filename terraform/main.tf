# Provider padrão: São Paulo (Brasil)
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

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "lacrei-igw" }
}

# Subnet A (São Paulo 1a)
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "sa-east-1a"
  map_public_ip_on_launch = true
  tags                    = { Name = "lacrei-public-a" }
}

# Subnet B (São Paulo 1c) - O ALB exige duas zonas!
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "sa-east-1c"
  map_public_ip_on_launch = true
  tags                    = { Name = "lacrei-public-b" }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

# --- CERTIFICADO TLS (AUTOASSINADO PARA O DESAFIO) ---
resource "tls_private_key" "example" {
  algorithm = "RSA"
}

resource "tls_self_signed_cert" "example" {
  private_key_pem = tls_private_key.example.private_key_pem

  subject {
    common_name  = "lacrei-saude.local"
    organization = "Lacrei Saude Challenge"
  }

  validity_period_hours = 8760 # 1 ano

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

resource "aws_iam_server_certificate" "lb_cert" {
  name_prefix      = "lacrei-cert-"
  certificate_body = tls_self_signed_cert.example.cert_pem
  private_key      = tls_private_key.example.private_key_pem
}

# --- Variables ---
variable "aws_region" { default = "sa-east-1" }
variable "app_runner_count" { default = 0 }
variable "ecr_repository_url" { type = string }
variable "environment" { default = "production" }
