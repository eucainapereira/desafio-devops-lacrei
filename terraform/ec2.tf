# --- Busca Automática pela AMI mais recente do Amazon Linux 2023 ---
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

# --- SG 1: Load Balancer (Aberto na Porta 80, 443 e 3001 para Grafana) ---
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
}

# --- SG 2: EC2 (Aceita APENAS do Load Balancer) ---
resource "aws_security_group" "ec2_sg" {
  name        = "lacrei-app-sg-${random_id.role_suffix.hex}"
  description = "Permitir transito vindo apenas do Load Balancer"
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
}

# --- Load Balancer (ALB) ---
resource "aws_lb" "app_lb" {
  name               = "lacrei-saude-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  enable_deletion_protection = false
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

# Ouvinte 80 (Redireciona para 443 App Oficial)
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

# Ouvinte 443 (HTTPS App Lacrei)
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

# Ouvinte 3001 (Grafana - HTTPS Seguro)
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

# --- IAM Role para a EC2 ---
resource "aws_iam_role" "ec2_ecr_role" {
  name = "lacrei-ec2-role-${random_id.role_suffix.hex}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ecr_attach" {
  role       = aws_iam_role.ec2_ecr_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_instance_profile" "ec2_profile" {
  name = "lacrei-ec2-profile-${random_id.role_suffix.hex}"
  role = aws_iam_role.ec2_ecr_role.name
}

# --- Instância EC2 (São Paulo) ---
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t3.micro"
  
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              usermod -a -G docker ec2-user
              
              # TENTATIVA DO DOCKER LOGIN (Pode falhar em casos de tempo excessivo da policy, mas rodará public images livremente)
              aws ecr get-login-password --region sa-east-1 | docker login --username AWS --password-stdin 873011686071.dkr.ecr.sa-east-1.amazonaws.com
              
              # Subir Aplicação Lacrei (Sua API original na 3000)
              docker pull 873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude:latest
              docker run -d -p 3000:3000 --name app-lacrei --restart always 873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude:latest

              # Subir GRAFANA (Porta 3001) para Desafio Monitoramento Bônus
              docker pull grafana/grafana-enterprise:latest
              docker run -d -p 3001:3000 --name grafana-monitor --restart always grafana/grafana-enterprise:latest
              EOF

  tags = { Name = "lacrei-saude-server" }
}

# Links dos Targets Groups
resource "aws_lb_target_group_attachment" "test" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = aws_instance.app_server.id
  port             = 3000
}

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana_tg.arn
  target_id        = aws_instance.app_server.id
  port             = 3001
}

# --- SNS Topic para Alertas (Bônus) ---
resource "aws_sns_topic" "alerts" {
  name = "lacrei-saude-alerts"
}

# --- Outputs atualizados ---
output "load_balancer_dns" {
  value = "https://${aws_lb.app_lb.dns_name}"
  description = "Acesse a aplicação principal (Retorna JSON com Message Bem Vindo)"
}

output "grafana_dashboard_url" {
  value       = "https://${aws_lb.app_lb.dns_name}:3001"
  description = "Acesse o painel seguro do Grafana (Monitoramento de Infraestrutura Bônus)"
}
