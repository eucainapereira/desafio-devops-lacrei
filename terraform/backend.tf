# ─────────────────────────────────────────────────────────────────────────────
# BACKEND REMOTO DO TERRAFORM — S3 + DynamoDB
#
# Por que S3 backend?
#   - O terraform.tfstate armazena todos os recursos criados. Mantê-lo apenas
#     localmente é arriscado: perda do arquivo = perda do controle da infra.
#   - Com S3, o state é versionado, criptografado e acessível pela CI/CD.
#
# Por que DynamoDB?
#   - Garante que apenas um `terraform apply` rode por vez (state lock).
#   - Evita corrupção do state em execuções paralelas (ex: dois PRs ao mesmo tempo).
#
# ATENÇÃO: O bucket S3 e a tabela DynamoDB devem ser criados UMA VEZ manualmente
# (ou via script bootstrap) ANTES do primeiro `terraform init`.
# Eles não podem ser gerenciados pelo próprio Terraform que os usa como backend.
#
# Comandos para criar o bootstrap (rodar apenas uma vez):
#
#   aws s3api create-bucket \
#     --bucket lacrei-tfstate-production \
#     --region sa-east-1 \
#     --create-bucket-configuration LocationConstraint=sa-east-1
#
#   aws s3api put-bucket-versioning \
#     --bucket lacrei-tfstate-production \
#     --versioning-configuration Status=Enabled
#
#   aws s3api put-bucket-encryption \
#     --bucket lacrei-tfstate-production \
#     --server-side-encryption-configuration \
#       '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
#
#   aws dynamodb create-table \
#     --table-name lacrei-tf-lock \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --billing-mode PAY_PER_REQUEST \
#     --region sa-east-1
# ─────────────────────────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.3.0"

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
    bucket         = "lacrei-tfstate-production"
    key            = "state/terraform.tfstate"
    region         = "sa-east-1"
    dynamodb_table = "lacrei-tf-lock"
    encrypt        = true
  }
}
