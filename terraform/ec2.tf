# ─────────────────────────────────────────────────────────────────────────────
# VARIÁVEIS ADICIONAIS
# ─────────────────────────────────────────────────────────────────────────────
variable "alert_email" {
  description = "E-mail que receberá os alertas do CloudWatch via SNS"
  type        = string
  default     = ""
}

variable "image_tag" {
  description = "Tag da imagem Docker a ser deployada (usado no rollback)"
  type        = string
  default     = "latest"
}

# ─────────────────────────────────────────────────────────────────────────────
# BUSCA AUTOMÁTICA PELA AMI MAIS RECENTE DO AMAZON LINUX 2023
# ─────────────────────────────────────────────────────────────────────────────
data "aws_ami" "latest_amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-20*-x86_64"]
  }
}

# Auxiliar para evitar conflitos de nomes se o state for perdido
resource "random_id" "role_suffix" {
  byte_length = 2
}

# ─────────────────────────────────────────────────────────────────────────────
# SECURITY GROUPS
# ─────────────────────────────────────────────────────────────────────────────

# SG 1: Load Balancer (Aberto nas portas 80, 443 e 3001 para Grafana)
resource "aws_security_group" "lb_sg" {
  name        = "lacrei-lb-sg-${random_id.role_suffix.hex}"
  description = "Acesso HTTP/HTTPS e Grafana para o Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Porta exclusiva do Grafana no LB
  ingress {
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lacrei-lb-sg" }
}

# SG 2: EC2 (Aceita APENAS do Load Balancer — sem exposição direta à internet)
resource "aws_security_group" "ec2_sg" {
  name        = "lacrei-app-sg-${random_id.role_suffix.hex}"
  description = "Permitir tráfego vindo apenas do Load Balancer"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  ingress {
    from_port       = 3001
    to_port         = 3001
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "lacrei-app-sg" }
}

# ─────────────────────────────────────────────────────────────────────────────
# LOAD BALANCER (ALB)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_lb" "app_lb" {
  name               = "lacrei-saude-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  # Proteção contra deleção acidental em produção
  enable_deletion_protection = true

  tags = {
    Name        = "lacrei-saude-alb"
    Environment = var.environment
  }
}

# Target Group da App (Porta 3000)
resource "aws_lb_target_group" "tg" {
  name_prefix = "lactg-"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/health"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Target Group do Grafana (Porta 3001)
resource "aws_lb_target_group" "grafana_tg" {
  name_prefix = "graf-"
  port        = 3001
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id

  health_check {
    path                = "/api/health"
    interval            = 60
    timeout             = 10
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Listener 80: Redireciona para 443
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Listener 443: HTTPS App Lacrei
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_iam_server_certificate.lb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# Listener 3001: Grafana HTTPS
resource "aws_lb_listener" "grafana" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "3001"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = aws_iam_server_certificate.lb_cert.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.grafana_tg.arn
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# IAM — ROLE DA EC2 (ECR + CloudWatch Agent + SSM Session Manager)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2_ecr_role" {
  name = "lacrei-ec2-role-${random_id.role_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })

  tags = { Name = "lacrei-ec2-role" }
}

# Permite fazer pull no ECR
resource "aws_iam_role_policy_attachment" "ec2_ecr_attach" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Permite CloudWatch Agent enviar logs e métricas
resource "aws_iam_role_policy_attachment" "ec2_cloudwatch_attach" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Permite acesso remoto via SSM Session Manager (sem abrir porta SSH)
resource "aws_iam_role_policy_attachment" "ec2_ssm_attach" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "lacrei-ec2-profile-${random_id.role_suffix.hex}"
  role = aws_iam_role.ec2_ecr_role.name
}

# ─────────────────────────────────────────────────────────────────────────────
# INSTÂNCIA EC2 (SÃO PAULO)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t3.micro"

  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              set -e
              yum update -y
              yum install -y docker amazon-cloudwatch-agent

              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user

              # ── CloudWatch Agent: coletar logs do Docker e métricas do sistema ──
              cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWCONFIG'
              {
                "logs": {
                  "logs_collected": {
                    "files": {
                      "collect_list": [
                        {
                          "file_path": "/var/lib/docker/containers/*/*.log",
                          "log_group_name": "/lacrei/app/docker",
                          "log_stream_name": "{instance_id}",
                          "timestamp_format": "%Y-%m-%dT%H:%M:%S"
                        }
                      ]
                    }
                  }
                },
                "metrics": {
                  "metrics_collected": {
                    "cpu": {
                      "measurement": ["cpu_usage_idle", "cpu_usage_user"],
                      "metrics_collection_interval": 60
                    },
                    "mem": {
                      "measurement": ["mem_used_percent"],
                      "metrics_collection_interval": 60
                    },
                    "disk": {
                      "measurement": ["used_percent"],
                      "resources": ["/"],
                      "metrics_collection_interval": 60
                    }
                  }
                }
              }
              CWCONFIG

              /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
                -a fetch-config \
                -m ec2 \
                -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
                -s

              # ── Login no ECR com retry (até 5 tentativas) ──
              for i in {1..5}; do
                aws ecr get-login-password --region sa-east-1 | \
                  docker login --username AWS --password-stdin 873011686071.dkr.ecr.sa-east-1.amazonaws.com && break
                echo "Tentativa $i falhou. Aguardando 10s..."
                sleep 10
              done

              # ── Pull e start da aplicação Lacrei (porta 3000) com retry ──
              for i in {1..5}; do
                docker pull 873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude:${var.image_tag} && break
                echo "Pull da imagem falhou (tentativa $i). Aguardando 15s..."
                sleep 15
              done

              docker run -d \
                -p 3000:3000 \
                --name app-lacrei \
                --restart always \
                --log-driver awslogs \
                --log-opt awslogs-region=sa-east-1 \
                --log-opt awslogs-group=/lacrei/app/docker \
                --log-opt awslogs-stream=app-lacrei \
                873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude:${var.image_tag}

              # ── Pull e start do Grafana (porta 3001) ──
              docker pull grafana/grafana-enterprise:latest
              docker run -d \
                -p 3001:3000 \
                --name grafana-monitor \
                --restart always \
                grafana/grafana-enterprise:latest

              EOF

  tags = {
    Name        = "lacrei-saude-server"
    Environment = var.environment
    Backup      = "true"
  }
}

# Associações dos Target Groups
resource "aws_lb_target_group_attachment" "app" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app_server.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana_tg.arn
  target_id        = aws_instance.app_server.id
  port             = 3001
}

# ─────────────────────────────────────────────────────────────────────────────
# OBSERVABILIDADE — CLOUDWATCH LOG GROUP
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/lacrei/app/docker"
  retention_in_days = 30

  tags = {
    Name        = "lacrei-app-logs"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# ALERTAS — SNS TOPIC + SUBSCRIPTION
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_sns_topic" "alerts" {
  name = "lacrei-saude-alerts"

  tags = {
    Name        = "lacrei-alerts"
    Environment = var.environment
  }
}

# Subscrição de e-mail para receber alertas
# NOTA: Após o apply, o e-mail receberá uma confirmação da AWS que deve ser aceita
resource "aws_sns_topic_subscription" "alert_email" {
  count     = var.alert_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ─────────────────────────────────────────────────────────────────────────────
# OBSERVABILIDADE — CLOUDWATCH ALARMS
# ─────────────────────────────────────────────────────────────────────────────

# Alarme 1: CPU da EC2 acima de 80% por 2 períodos consecutivos de 5 min
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  alarm_name          = "lacrei-ec2-high-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Alerta: CPU da EC2 acima de 80% por 10 minutos consecutivos"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    InstanceId = aws_instance.app_server.id
  }

  tags = { Name = "lacrei-cpu-alarm" }
}

# Alarme 2: Hosts não saudáveis no Target Group da aplicação
resource "aws_cloudwatch_metric_alarm" "unhealthy_hosts" {
  alarm_name          = "lacrei-alb-unhealthy-hosts"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Alerta: Instâncias não saudáveis detectadas no Target Group do ALB"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    TargetGroup  = aws_lb_target_group.tg.arn_suffix
    LoadBalancer = aws_lb.app_lb.arn_suffix
  }

  tags = { Name = "lacrei-unhealthy-alarm" }
}

# Alarme 3: Erros HTTP 5xx no ALB (indicativo de falha na aplicação)
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "lacrei-alb-5xx-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_description   = "Alerta: Mais de 10 erros HTTP 5xx em 10 minutos"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    LoadBalancer = aws_lb.app_lb.arn_suffix
  }

  tags = { Name = "lacrei-5xx-alarm" }
}

# ─────────────────────────────────────────────────────────────────────────────
# RESILIÊNCIA — SSM PARAMETER STORE (base do rollback automático)
# ─────────────────────────────────────────────────────────────────────────────
resource "aws_ssm_parameter" "last_deployed_image_tag" {
  name        = "/lacrei/last-successful-image-tag"
  type        = "String"
  value       = var.image_tag
  description = "Tag da última imagem Docker deployada com sucesso (usada no rollback automático)"
  overwrite   = true

  tags = {
    Name        = "lacrei-last-image-tag"
    Environment = var.environment
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# OUTPUTS
# ─────────────────────────────────────────────────────────────────────────────
output "load_balancer_dns" {
  value       = "https://${aws_lb.app_lb.dns_name}"
  description = "URL principal da aplicação (via Load Balancer HTTPS)"
}

output "grafana_dashboard_url" {
  value       = "https://${aws_lb.app_lb.dns_name}:3001"
  description = "URL do painel Grafana (monitoramento)"
}

output "cloudwatch_log_group" {
  value       = aws_cloudwatch_log_group.app_logs.name
  description = "Nome do Log Group no CloudWatch"
}

output "sns_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "ARN do tópico SNS para alertas"
}

output "ssm_rollback_parameter" {
  value       = aws_ssm_parameter.last_deployed_image_tag.name
  description = "Parâmetro SSM que guarda a tag da última imagem estável"
}
