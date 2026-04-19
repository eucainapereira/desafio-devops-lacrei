# Desafio Técnico DevOps - Lacrei Saúde 🚀

Este repositório contém a solução completa para o desafio técnico de DevOps da Lacrei Saúde. O projeto consiste em uma esteira de CI/CD automatizada para uma aplicação Node.js, utilizando infraestrutura moderna na AWS gerenciada via Terraform.

## 🏗️ Arquitetura do Projeto

Para este desafio, optei por uma abordagem **Híbrida e Multirregional** para garantir performance e conformidade com os serviços disponíveis na AWS:

*   **Ambiente de Produção (São Paulo - sa-east-1)**: Implantado em **Amazon EC2** para garantir a menor latência possível para usuários no Brasil.
*   **Ambiente de Staging (Virgínia - us-east-1)**: Configurado utilizando **AWS App Runner** (Cloud Native). Como este serviço ainda não está disponível na região de São Paulo, a arquitetura foi desenhada para operar de forma multirregional, demonstrando versatilidade na gestão de recursos globais. (Como eu uso o free tier para subir subir a infraestrutura, o plano free tier da AWS não dá acesso ao serviço App Runner, porém mesmo assim o código foi criado com a expectativa de que esse serviço esteja funcionando com um detalhe, no main.tf o recurso: [variable "app_runner_count" { default = 0 }] faz com que o serviço não funcione pulando assim essa etapa para o deploy ser aceito.)

## 🛠️ Tecnologias Utilizadas

*   **Docker**: Conteinerização da aplicação Node.js.
*   **Terraform**: Infraestrutura como Código (IaC) para provisionamento de VPC, Subnets, Security Groups e instâncias.
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

*   **Security Groups**: Portas de entrada restritas apenas ao necessário (80 para o tráfego HTTP e 3000 para a aplicação).
*   **User Data Resiliente**: O script de inicialização da EC2 conta com lógica de retry, login automático no ECR e reinicialização automática do container em caso de falha.
*   **GitHub Secrets**: Nenhuma credencial sensível está exposta no código.

## 📈 Como visualizar a aplicação

A aplicação de produção pode ser acessada através do IP Público gerado pelo Terraform na região de São Paulo:

*   **IP de Produção**: [[Link para o IP atualizado]](http://54.207.253.176/)
*   **Porta**: 80 (HTTP)

---
*Projeto desenvolvido por Cainã Pereira como requisito para o Desafio Técnico de DevOps da Lacrei Saúde.*
