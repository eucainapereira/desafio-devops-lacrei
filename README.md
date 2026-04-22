# Desafio Técnico DevOps — Lacrei Saúde 🚀

Este repositório contém a solução completa para o desafio técnico de DevOps da Lacrei Saúde: uma esteira de CI/CD automatizada para uma aplicação Node.js, com infraestrutura na AWS gerenciada integralmente via Terraform.

---

## 🏗️ Arquitetura

```
                          ╔══════════════════╗
                          ║   Desenvolvedor  ║
                          ╚════════╦═════════╝
                                   │ git push
                          ╔════════▼═════════╗
                          ║  GitHub Actions  ║
                          ║ ┌──────────────┐ ║
                          ║ │ 1. Lint      │ ║
                          ║ │ 2. Testes    │ ║
                          ║ │ 3. Build     │ ║
                          ║ │ 4. Trivy Scan│ ║
                          ║ │ 5. Push ECR  │ ║
                          ║ │ 6. TF Plan   │ ║
                          ║ │ 7. TF Apply  │ ║
                          ║ │ 8. Smoke Test│ ║
                          ║ └──────────────┘ ║
                          ╚══════╦═══════════╝
                                 │
               ┌─────────────────┼──────────────────┐
               ▼                 ▼                   ▼
         ┌─────────┐      ┌──────────┐       ┌───────────┐
         │   ECR   │      │S3 TFState│       │  DynamoDB │
         │(imagens)│      │(tfstate) │       │(state lock│
         └─────────┘      └──────────┘       └───────────┘
               │
               ▼
    ╔══════════════════════╗
    ║     AWS — sa-east-1  ║
    ║  ┌────────────────┐  ║
    ║  │ Internet (80)  │  ║  ← Redireciona para HTTPS
    ║  │ Internet (443) │  ║  ← HTTPS/TLS (App)
    ║  │ Internet (3001)│  ║  ← HTTPS/TLS (Grafana)
    ║  └───────┬────────┘  ║
    ║          │           ║
    ║  ┌───────▼────────┐  ║
    ║  │      ALB       │  ║  ← Application Load Balancer
    ║  │ (sa-east-1a/c) │  ║     deletion_protection=true
    ║  └───────┬────────┘  ║
    ║          │           ║
    ║  ┌───────▼────────┐  ║
    ║  │  EC2 t3.micro  │  ║  ← Aceita APENAS do ALB (SG restrito)
    ║  │  :3000 (App)   │  ║
    ║  │  :3001 (Grafana│  ║
    ║  └───────┬────────┘  ║
    ║          │           ║
    ║  ┌───────▼────────┐  ║
    ║  │  CloudWatch    │  ║  ← Logs + Métricas + Alarmes → SNS → E-mail
    ║  └────────────────┘  ║
    ║                      ║
    ║  ┌────────────────┐  ║
    ║  │  SSM Parameter │  ║  ← Guarda tag da última imagem estável (rollback)
    ║  └────────────────┘  ║
    ╚══════════════════════╝
```

---

## 🛠️ Tecnologias

| Camada | Tecnologia | Função |
|---|---|---|
| **Aplicação** | Node.js + Express | API com logs JSON estruturados |
| **Segurança App** | Helmet + CORS | Proteção de headers HTTP |
| **Contêiner** | Docker | Empacotamento e execução isolada |
| **Registry** | Amazon ECR | Armazenamento privado de imagens |
| **IaC** | Terraform >= 1.3 | Provisionamento declarativo da infra |
| **State Backend** | S3 + DynamoDB | State remoto, versionado e com lock |
| **CI/CD** | GitHub Actions | Pipeline automático de 7 jobs |
| **Segurança Imagem** | Trivy | Scan de vulnerabilidades CRITICAL |
| **Compute** | EC2 t3.micro | Servidor de aplicação em São Paulo |
| **Balanceamento** | ALB | Distribuição de tráfego + TLS termination |
| **Criptografia** | TLS self-signed (IAM) | HTTPS obrigatório (demo sem domínio) |
| **Logs** | CloudWatch Logs | Coleta de logs estruturados dos containers |
| **Métricas** | CloudWatch + CW Agent | CPU, memória, disco, HTTP 5xx |
| **Alertas** | CloudWatch Alarms + SNS | Notificação por e-mail em incidentes |
| **Monitoramento** | Grafana Enterprise | Dashboard visual de métricas |
| **Rollback** | SSM Parameter Store | Guarda tag da última imagem estável |
| **Acesso Remoto** | SSM Session Manager | Acesso à EC2 sem SSH exposto |

---

## 🚀 Pipeline CI/CD

O pipeline está em `.github/workflows/main.yml` e possui **7 jobs encadeados**:

```
[lint] ──► [test] ──► [build+scan+push] ──► [terraform-plan] ──► [deploy-prod] ──► [rollback*]
                               │
                               └──► [deploy-staging] (branch: staging)

* rollback só ativa em caso de falha no deploy-prod
```

### Detalhamento dos Jobs

| # | Job | O que faz | Gate de qualidade |
|---|---|---|---|
| 1 | **lint** | Roda `npm run lint` (ESLint) | Bloqueia se houver erros de código |
| 2 | **test** | Roda `npm test` (Jest) | Bloqueia se testes falharem |
| 3 | **build+scan+push** | Build Docker → Trivy Scan → Push ECR | Bloqueia em vulnerabilidades CRITICAL |
| 4 | **terraform-plan** | Gera `terraform plan` e salva como artefato | Gate visual antes do apply |
| 5 | **deploy-production** | `terraform apply` → SSM update → Smoke Test | Smoke test valida HTTP 200 no ALB |
| 6 | **deploy-staging** | App Runner (Virgínia) | Apenas na branch `staging` |
| 7 | **rollback** | Busca imagem estável no SSM e faz re-apply | Acionado automaticamente em falha |

### Secrets Necessários no GitHub

| Secret | Descrição | Obrigatório |
|---|---|---|
| `AWS_ACCESS_KEY_ID` | Chave de acesso IAM do pipeline | ✅ Sim |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta IAM do pipeline | ✅ Sim |
| `ALERT_EMAIL` | E-mail que receberá alertas do CloudWatch | ⚡ Recomendado |

---

## 🔒 Segurança

### Defense in Depth (Defesa em Profundidade)

```
Internet
   │
   ▼  Camada 1: ALB Security Group (port 80/443/3001 only)
   │
   ▼  Camada 2: TLS/HTTPS obrigatório (redirect 80→443, SG bloqueia HTTP direto)
   │
   ▼  Camada 3: EC2 Security Group (aceita APENAS do ALB — sem exposição direta)
   │
   ▼  Camada 4: IAM Least Privilege (GitHub Actions e EC2 com permissões mínimas)
   │
   ▼  Camada 5: Trivy Scan (bloqueia imagens com CVEs CRITICAL)
   │
   ▼  Camada 6: Secrets via GitHub Secrets / variáveis de ambiente
```

### Checklist de Segurança

- [x] **Least Privilege (IAM)**: Políticas restritas por serviço e por ARN
- [x] **Isolamento de Rede**: EC2 sem exposição direta — tráfego apenas via ALB
- [x] **HTTPS/TLS Obrigatório**: Listener 80 redireciona para 443 (HTTP_301)
- [x] **Secrets sem exposição**: Credenciais injetadas via GitHub Secrets
- [x] **Scan de Imagens**: Trivy bloqueia vulnerabilidades CRITICAL antes do push
- [x] **ECR scan_on_push**: Escaneamento automático no registro
- [x] **Acesso remoto seguro**: SSM Session Manager (sem porta SSH aberta)
- [x] **State criptografado**: S3 com SSE-AES256 + versionamento habilitado
- [x] **ALB Deletion Protection**: Proteção contra deleção acidental em produção

---

## 📊 Observabilidade

### O que é coletado

| Fonte | Destino | Como visualizar |
|---|---|---|
| Logs JSON da aplicação | CloudWatch Log Group `/lacrei/app/docker` | CloudWatch Logs Insights |
| Logs do Docker (stdout) | CloudWatch Log Group via CW Agent | CloudWatch Logs Insights |
| CPU, memória, disco da EC2 | CloudWatch Metrics (namespace `CWAgent`) | Grafana ou CloudWatch |
| Métricas do ALB (latência, 5xx) | CloudWatch Metrics (namespace `AWS/ApplicationELB`) | CloudWatch |

### Alarmes Configurados

| Alarme | Condição | Ação |
|---|---|---|
| `lacrei-ec2-high-cpu` | CPU > 80% por 10 min consecutivos | SNS → E-mail |
| `lacrei-alb-unhealthy-hosts` | Hosts não saudáveis > 0 no Target Group | SNS → E-mail |
| `lacrei-alb-5xx-errors` | Mais de 10 erros HTTP 5xx em 10 min | SNS → E-mail |

### Logs Estruturados da Aplicação

Todo request gera um log JSON com a seguinte estrutura:
```json
{
  "timestamp": "2025-01-15T14:30:00.000Z",
  "level": "INFO",
  "method": "GET",
  "url": "/health",
  "status": 200,
  "responseTimeMs": 12,
  "ip": "10.0.1.5",
  "environment": "production"
}
```

Consulta de exemplo no **CloudWatch Logs Insights**:
```
fields @timestamp, method, url, status, responseTimeMs
| filter status >= 500
| sort @timestamp desc
| limit 50
```

---

## 🔄 Estratégia de Rollback

### Rollback Automático (via GitHub Actions)

Em caso de falha no `deploy-production` (smoke test retorna status != 200), o job `rollback` é acionado automaticamente:

1. Consulta o **SSM Parameter Store** `/lacrei/last-successful-image-tag`
2. Obtém a tag SHA do último deploy bem-sucedido
3. Executa `terraform apply` com a imagem estável

### Rollback Manual

**Via GitHub Actions (Recomendado)**:
1. Vá na aba **Actions** do repositório
2. Selecione o último workflow bem-sucedido
3. Clique em **Re-run all jobs**

**Via Terraform (Emergência)**:
```bash
# Verificar a última tag estável
aws ssm get-parameter --name "/lacrei/last-successful-image-tag" --output text --query Parameter.Value

# Aplicar manualmente com a tag desejada
cd terraform
terraform apply -var="ecr_repository_url=873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude" \
                -var="image_tag=<sha-do-commit>"
```

---

## 📈 Resiliência e Alta Disponibilidade

### Atual (v2 — Free Tier)

- EC2 single instance com `--restart always` (auto-recuperação do container)
- ALB com **health check** automático → remove instâncias não saudáveis do pool
- **User data com retry** (5 tentativas de pull da imagem, backoff de 15s)
- **Alarmes automáticos** notificam em falha
- **Rollback automático** em falha de pipeline

### Proposta Futura (Auto Scaling Group)

O arquivo `terraform/autoscaling.tf` documenta a arquitetura de ASG completamente comentada, pronta para ativar quando o orçamento permitir:

- **min=1, max=3** instâncias (scale automático por CPU > 70%)
- Distribuição em **múltiplas AZs** (sa-east-1a + sa-east-1c)
- **Self-healing**: substituição automática de instâncias com falha
- **Rolling update**: substituição gradual sem downtime

---

## 🗃️ Decisões Arquiteturais

| Problema / Cenário | Decisão e Justificativa |
|:---|:---|
| **App Runner não disponível no Free Tier**<br>Deploy falhava com `SubscriptionRequiredException` | `app_runner_count = 0` como feature toggle inteligente. O código permanece funcional e documentado para ativação futura sem refatoração |
| **State corruption em múltiplos applies**<br>`EntityAlreadyExists` ao recriar recursos | S3 backend com DynamoDB lock: garante atomicidade e histórico de versões do state. `name_prefix` no lugar de `name` para evitar conflitos de nomenclatura |
| **Chaves IAM de longa duração**<br>GitHub Actions com `Access Key ID` | Mantidas por limitação do Free Tier (OIDC exige permissões de admin para configurar o Identity Provider). Compensado com Trivy scan e escopo IAM mínimo |
| **CloudWatch vs Prometheus standalone**<br>Escolha da pilha de observabilidade | CloudWatch reutiliza o Free Tier existente (10 alarmes gratuitos) e se integra nativamente com SNS e ALB. Grafana acoplado como container para dashboards visuais imediatos |
| **ASG vs EC2 single instance**<br>Escalabilidade vs custo | EC2 single instance para o desafio (Free Tier). ASG documentado como proposta em `autoscaling.tf` — ativação não exige refatoração, apenas descomentar |
| **Self-signed TLS vs ACM**<br>Certificado HTTPS | Self-signed via `tls_private_key` + `tls_self_signed_cert` (sem domínio registrado no desafio). Em produção real: ACM + Route53 para certificado gerenciado e renovação automática |

---

## 🔔 Bônus: Integração Asaas (Arquitetura Proposta)

```
[Asaas] ──► [API Gateway] ──► [Lambda] ──► [DB Lacrei Saúde]
```

1. **Asaas** envia evento de pagamento para um **AWS API Gateway**
2. O Gateway dispara uma **Lambda** (serverless) para processar o evento
3. A Lambda atualiza o banco de dados sem onerar o servidor principal

---

## 🛠️ Como Replicar do Zero

### Pré-requisitos
- Conta AWS com permissões IAM configuradas (ver política no repo)
- Terraform >= 1.3 instalado localmente
- AWS CLI configurado

### Passo 1: Configurar Secrets no GitHub

> **✅ O bucket S3 e a tabela DynamoDB são criados automaticamente pelo pipeline no primeiro push.**
> O job `bootstrap-backend` verifica se os recursos existem e os cria caso necessário — 100% idempotente, sem nenhuma ação manual.

Em **Settings → Secrets and variables → Actions**, adicione:

| Secret | Valor |
|---|---|
| `AWS_ACCESS_KEY_ID` | Chave de acesso do IAM user do pipeline |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta do IAM user |
| `ALERT_EMAIL` | E-mail para receber alertas do CloudWatch |

### Passo 2: Ativar o Pipeline

```bash
git clone https://github.com/eucainapereira/desafio-devops-lacrei.git
cd desafio-devops-lacrei
git push origin main   # Dispara o pipeline completo
```

### Passo 3: Confirmar Subscription do SNS

Após o primeiro `terraform apply`, o e-mail configurado receberá uma confirmação da AWS. **Clique no link de confirmação** para começar a receber alertas.

### Passo 4: Destruir o Ambiente (Limpeza de Custos)

```bash
# Desabilitar o deletion_protection do ALB antes de destruir
aws elbv2 modify-load-balancer-attributes \
  --load-balancer-arn $(aws elbv2 describe-load-balancers --names lacrei-saude-alb --query "LoadBalancers[0].LoadBalancerArn" --output text) \
  --attributes Key=deletion_protection.enabled,Value=false \
  --region sa-east-1

cd terraform
terraform destroy -auto-approve
```

---

*Projeto desenvolvido por Cainã Pereira como requisito para o Desafio Técnico de DevOps da Lacrei Saúde.*
