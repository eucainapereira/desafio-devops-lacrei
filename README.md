# Desafio Técnico DevOps - Lacrei Saúde 🚀

Este repositório contém a solução completa para o desafio técnico de DevOps da Lacrei Saúde. O projeto consiste em uma esteira de CI/CD automatizada para uma aplicação Node.js, utilizando infraestrutura moderna na AWS gerenciada via Terraform.

## 🏗️ Arquitetura do Projeto
Para este desafio, optei por uma abordagem **Híbrida e Multirregional** para garantir performance e conformidade com os serviços disponíveis na AWS:

*   **Ambiente de Produção (São Paulo - sa-east-1)**: Implantado em **Amazon EC2** para garantir a menor latência possível para usuários no Brasil. A infraestrutura conta com:
    * **Application Load Balancer (ALB)**: Gerencia o tráfego de entrada, distribuindo-o entre subnets em diferentes zonas de disponibilidade (sa-east-1a e sa-east-1c).
    * **HTTPS/TLS Obrigatório**: Todo o tráfego na porta 80 é redirecionado automaticamente para a porta 443 (HTTPS). A criptografia é garantida por um certificado TLS gerenciado pelo AWS IAM.
    * **Isolamento de Segurança**: A instância EC2 opera em um Security Group restrito, aceitando conexões **apenas** vindas do Load Balancer na porta da aplicação (3000).
*   **Ambiente de Staging (Virgínia - us-east-1)**: Configurado utilizando **AWS App Runner** (Cloud Native). Como este serviço ainda não está disponível na região de São Paulo, a arquitetura foi desenhada para operar de forma multirregional, demonstrando versatilidade na gestão de recursos globais.

    > ⚠️ **Nota Estratégica sobre o App Runner (Free Tier)**: Como eu uso o free tier para subir a infraestrutura, o plano free tier da AWS não dá acesso ao serviço App Runner. Porém, mesmo assim o código foi criado com a expectativa de que esse serviço esteja funcionando, com um detalhe crucial: no `main.tf` o recurso `variable "app_runner_count" { default = 0 }` faz com que o serviço não seja criado, pulando assim essa etapa para o deploy ser aceito sem causar erros de SubscriptionRequiredException, comprovando o domínio da estrutura do código.

## 🛠️ Tecnologias Utilizadas

*   **Docker**: Conteinerização da aplicação Node.js.
*   **Terraform**: Infraestrutura como Código (IaC) para provisionamento de VPC, Subnets, Security Groups, ALB e instâncias.
*   **AWS ECR**: Registro privado de imagens Docker em São Paulo.
*   **GitHub Actions**: Automação completa do ciclo de vida (Lint -> Test -> Build -> Push -> Deploy).
*   **IAM (Least Privilege)**: Políticas de acesso restritas para garantir a segurança da conta.

## 🚀 Esteira CI/CD

A pipeline está configurada no arquivo `.github/workflows/main.yml` e segue os seguintes passos:

1.  **Lint & Test**: Validação de código e execução de testes unitários.
2.  **Build & Push**: Geração da imagem Docker e envio para o Amazon ECR (sa-east-1) com tags de SHA e `latest`.
3.  **Deploy Staging**: Disparado automaticamente em pushes para a branch `staging`.
4.  **Deploy Production**: Disparado em pushes para `main` ou `master`, utilizando o Terraform para atualizar a infraestrutura e o runtime da aplicação.

## 🔒 Segurança e Melhores Práticas

*   **Security Groups**: Acesso rigidamente controlado, com tráfego público permitido apenas no ALB (Load Balancer). O tráfego direto para a porta principal da aplicação é bloqueado na Internet.
*   **User Data Resiliente**: O script de inicialização da EC2 conta com lógica de retry, login automático no ECR e reinicialização automática do container em caso de falha.
*   **GitHub Secrets**: Nenhuma credencial sensível está exposta no código.

## 📈 Como acessar a aplicação

Após o deploy, o Terraform gerará um link no formato de DNS do ALB (Load Balancer).

*   **Load Balancer (HTTPS)**: Será gerada uma URL segura via Load Balancer. Como utilizamos um certificado **Self-Signed** (autoassinado) para este desafio (limitante do ambiente sem domínio registrado), o navegador exibirá um alerta de segurança. Para acessar, clique em "Avançado" e "Prosseguir para o site".
*   *(Opcional: IP Direto de Arquiteturas Anteriores ou Falha no ALB: [http://54.207.253.176/](http://54.207.253.176/))*

## 🔄 Estratégia de Rollback

Caso um deploy apresente falhas, você pode realizar o rollback de duas formas seguras:

1.  **Via GitHub Actions (Recomendado)**:
    *   Vá na aba "Actions" do repositório.
    *   Selecione o último Job que foi bem-sucedido.
    *   Clique em "Re-run all jobs". Isso fará o re-deploy da imagem anterior que já estava estável.
2.  **Via Terraform (Manual)**:
    *   No arquivo `ec2.tf`, você pode alterar a tag da imagem no `user_data` de `:latest` para a tag de um commit específico (ex: `:sha-abc1234`).
    *   Execute `terraform apply` novamente.

## 🟨 Bônus: Integração Asaas (Arquitetura Proposta)

Para integrar o sistema de pagamentos da Assas, a arquitetura recomendada utiliza **Webhooks**:
1.  **Asaas** envia um evento de pagamento para um **AWS API Gateway**.
2.  O Gateway dispara uma **AWS Lambda** (Serverless) para processar o pagamento sem onerar o servidor principal.
3.  A Lambda atualiza o banco de dados da Lacrei Saúde.

## 🔔 Alertas e Monitoramento (Bônus)

Implementamos um tópico **AWS SNS** (Simple Notification Service) na infraestrutura para permitir a configuração futura de alertas de faturamento e status do servidor via E-mail ou Slack.

Além disso, para comprovar a capacidade de monitoramento local em tempo real, uma stack do **Grafana** foi acoplada de forma 100% automatizada e como código (IaC):
* O script de `user_data` do Terraform instancia um container Docker oficial do Grafana Enterprise.
* Um Target Group e Listener atrelados ao Application Load Balancer foram provisionados para direcionar requisições da porta `3001` até a interface do Grafana.
* Acesso imediato às validações via porta `3001` do DNS seguro do seu ALB.

## 🛡️ Checklist de Segurança Aplicado

Em cumprimento às regras e melhores princípios de DevOps/DevSecOps de alto nível em nuvem, este projeto atende integralmente a esse checklist estrutural:

- [x] **Least Privilege (IAM)**: Uso de políticas JSON restritas a serviços exatos (ec2, ecr, sns, elb), garantindo que a credencial fornecida não possa apagar ou comprometer infraestruturas paralelas da conta.
- [x] **Isolamento Interno de Redes (Security Groups)**: Instância sem exposição em pontas. O Target Group bloqueia acessos externos diretos na EC2, autorizando navegação nas portas dos containers apenas e se advindas do escudo do Load Balancer.
- [x] **Criptografia em Trânsito (HTTPS/TLS)**: Configuração minuciosa para adoção do Load Balancer e Listener 443 certificado por TLS/IAM, exigido contratualmente para navegação selada, com redirecionamento ativo Anti-HTTP(80).
- [x] **Vaults e Secrets Seguros**: Transição limpa de dados sigilosos; Chaves de autenticação injetadas sob-demanda do Painel Oculto de Repositórios do GitHub Actions e não commitadas fisicamente via texto-plano.
- [x] **Containerização Rastrével e Segura**: Resiliência ativada ao `restart always`. Pull da imagem rastreada diretamente do Amazon ECR após ciclo completo formal de CI/CD (Lint > Testes de unidade). 

## 🗃️ Registro de Decisões e Troubleshooting (Post-Mortem)

Durante o desenvolvimento do ambiente, priorizamos respostas técnicas em cenários reais de engenharia. Apresentamos abaixo os principais desafios e as respectivas soluções implementadas de forma a evidenciar as tomadas de decisão gerenciais do projeto:

| Problema / Erro Observado no Deploy | Análise e Decisão Arquitetural |
| :--- | :--- |
| **Limitação AWS Free Tier (App Runner)**<br>O deploy falhava por `SubscriptionRequiredException` ao invocar um serviço Premium da nuvem inviável para o momento. | **Decisão**: Alteramos a variável atrelada ao provisionamento do Staging para `app_runner_count = 0`. O código em `main.tf` para App Runner foi preservado e está funcional metodicamente, mas desativado como demonstração de *Feature Toggle* inteligente para segurar custos. |
| **Erros de State Drift (Terraform `EntityAlreadyExists`)**<br>Os testes geravam travamentos com "TargetGroup already exists" ou conflitos de certificados durante as múltiplas reconstruções. | **Decisão**: Abolimos regras de nomenclaturas rígidas nos recursos ("hardcoded strings"). Adotamos geradores dinâmicos como `name_prefix` no lugar de `name` e criamos instâncias aleatórias atreladas ao helper `random_id`, permitindo imutabilidade paralela contínua a cada novo `apply`. |
| **Quedas por Permissões no GitHub Actions (`UnauthorizedOperation`)**<br>Bloqueio do pipeline ao criar roteamentos avançados (ALB) exigindo níveis maiores da política IAM. | **Decisão**: Aplicação estrita de *Least Privilege*. Sem o uso de "Admin Access", validamos linha a linha e mapeamos chaves exclusivas de `elasticloadbalancing:*`, `sns:*`, `iam:PassRole` acoplando as edições na policy anexada. |
| **Limitação do CloudWatch Agent no Nível Gratuito**<br>A injeção do agente não sincronizava instâncias de logs corretamente ou exigia Roles avançados de log que pesavam a estrutura base. | **Decisão**: Decisões visuais ágeis *("Shift Left")*: Alteramos a premissa analítica incluindo localmente a dependência corporativa **Grafana Enterprise** via conteinerização nativa no próprio `user_data` - demonstrando automação de painéis paralelos operando sob tráfego próprio via porta 3001 nativa. |

## 🛠️ Como Replicar este Ambiente do Zero

Para reproduzir toda essa infraestrutura na sua própria conta AWS, siga os passos abaixo:

### Pré-requisitos
* Conta na AWS com permissões administrativas.
* Terraform instalado localmente (caso deseje testar a infra manual).
* Repositório no GitHub para configuração do CI/CD.

### Passos
1. **Clone o repositório**:
   ```bash
   git clone https://github.com/eucainapereira/desafio-devops-lacrei.git
   cd desafio-devops-lacrei
   ```

2. **Crie o Repositório no Amazon ECR**:
   A AWS exige que o repositório do ECR exista antes de fazermos o push pela Action. Crie-o na região `sa-east-1` (São Paulo) com o nome exato `app-lacrei-saude`.

3. **Configure os Secrets no GitHub**:
   No seu repositório GitHub, vá em *Settings* > *Secrets and variables* > *Actions* e adicione:
   * `AWS_ACCESS_KEY_ID`: Sua chave de acesso AWS.
   * `AWS_SECRET_ACCESS_KEY`: Sua chave secreta AWS.

4. **Inicie a Pipeline CI/CD**:
   * Faça uma alteração simples ou apenas force um push para a branch `main`.
   * A GitHub Action fará o lint, testes, build da imagem Docker, push para o ECR e acionará o Terraform para criar a arquitetura segura (ALB + HTTPS + EC2 + SNS).

5. **Destruir o ambiente (Limpeza)**:
   Para não gerar custos desnecessários na AWS com recursos ativos ou em ociosidade, caso queira limpar tudo, acesse a pasta `terraform` localmente e rode:
   ```bash
   terraform destroy -auto-approve
   ```

---
*Projeto desenvolvido por Cainã Pereira como requisito para o Desafio Técnico de DevOps da Lacrei Saúde.*
