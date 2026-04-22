# ─────────────────────────────────────────────────────────────────────────────
# BACKEND REMOTO DO TERRAFORM — S3 com locking nativo
#
# Por que S3 backend?
#   - O terraform.tfstate armazena todos os recursos criados. Mantê-lo apenas
#     localmente é arriscado: perda do arquivo = perda do controle da infra.
#   - Com S3, o state é versionado, criptografado e acessível pela CI/CD.
#
# Por que use_lockfile em vez de DynamoDB?
#   - A partir do Terraform >= 1.10, o S3 backend suporta locking nativo
#     via conditional writes (sem precisar de uma tabela DynamoDB separada).
#   - Mais simples: menos recursos para gerenciar, mesmo nível de segurança.
#
# O bucket S3 é criado automaticamente pelo job bootstrap-backend no pipeline.
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "lacrei-tfstate-production"
    key          = "state/terraform.tfstate"
    region       = "sa-east-1"
    use_lockfile = true   # Locking nativo S3 — não requer DynamoDB (Terraform >= 1.10)
    encrypt      = true
  }
}
