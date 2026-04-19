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

# --- Security Group para a EC2 (Usa o provedor padrão de São Paulo) ---
resource "aws_security_group" "ec2_sg" {
  name        = "lacrei-app-sg-${random_id.role_suffix.hex}"
  description = "Permitir transito para a app Lacrei"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
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

# --- IAM Role para a EC2 acessar o ECR ---
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

# --- Instancia EC2 (São Paulo) ---
resource "aws_instance" "app_server" {
  ami           = data.aws_ami.latest_amazon_linux.id
  instance_type = "t3.micro"
  
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.ec2_profile.name
  associate_public_ip_address = true

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y docker
              systemctl start docker
              systemctl enable docker
              
              aws ecr get-login-password --region sa-east-1 | docker login --username AWS --password-stdin 873011686071.dkr.ecr.sa-east-1.amazonaws.com
              docker run -d -p 80:3000 --name app-lacrei 873011686071.dkr.ecr.sa-east-1.amazonaws.com/app-lacrei-saude:latest
              EOF

  tags = {
    Name = "lacrei-saude-server"
  }
}

output "ec2_public_ip" {
  value = aws_instance.app_server.public_ip
}
