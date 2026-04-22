# ═══════════════════════════════════════════════════════════════════════════════
# PROPOSTA ARQUITETURAL: AUTO SCALING GROUP (ASG)
#
# ⚠️  ESTE ARQUIVO ESTÁ COMPLETAMENTE COMENTADO — NÃO CRIA RECURSOS NA AWS ⚠️
#
# OBJETIVO:
#   Documentar como a infraestrutura atual (EC2 single instance) pode evoluir
#   para um modelo de alta disponibilidade com escala automática, sem precisar
#   reconstruir toda a arquitetura. É um "Feature Toggle" — quando o momento e
#   orçamento permitirem, basta descomentar e ajustar as variáveis.
#
# O QUE RESOLVE:
#   - Elimina o Single Point of Failure (SPOF) da instância EC2 atual
#   - Escala automaticamente sob carga (CPU > 70%)
#   - Substitui instâncias com falha automaticamente (self-healing)
#   - Distribui carga em múltiplas Zonas de Disponibilidade (sa-east-1a e 1c)
#
# CUSTO ESTIMADO (quando ativado):
#   - t3.micro: Free Tier (750h/mês)
#   - Múltiplas instâncias: pagamento sob demanda (~$0.0104/hora por instância adicional)
#
# COMO ATIVAR:
#   1. Renomeie este arquivo para autoscaling.tf e remova todos os # dos blocos
#   2. Certifique-se de remover o recurso aws_instance "app_server" do ec2.tf
#      (o ASG substitui a instância gerenciada manualmente)
#   3. Atualize os Target Groups para apontar para o ASG (remova aws_lb_target_group_attachment)
#   4. Execute terraform apply
# ═══════════════════════════════════════════════════════════════════════════════


# ── Launch Template: define a configuração de cada nova instância no ASG ──────
#
# resource "aws_launch_template" "app_lt" {
#   name_prefix   = "lacrei-app-lt-"
#   image_id      = data.aws_ami.latest_amazon_linux.id
#   instance_type = "t3.micro"
#
#   iam_instance_profile {
#     name = aws_iam_instance_profile.ec2_profile.name
#   }
#
#   vpc_security_group_ids = [aws_security_group.ec2_sg.id]
#
#   # O mesmo user_data do ec2.tf é reutilizado aqui
#   user_data = base64encode(<<-EOF
#     #!/bin/bash
#     # (mesmo script de inicialização do ec2.tf)
#     EOF
#   )
#
#   monitoring {
#     enabled = true
#   }
#
#   tag_specifications {
#     resource_type = "instance"
#     tags = {
#       Name        = "lacrei-asg-instance"
#       Environment = var.environment
#       ManagedBy   = "ASG"
#     }
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }


# ── Auto Scaling Group ────────────────────────────────────────────────────────
#
# resource "aws_autoscaling_group" "app_asg" {
#   name_prefix         = "lacrei-asg-"
#   min_size            = 1      # Mínimo: 1 instância sempre ativa
#   max_size            = 3      # Máximo: até 3 instâncias sob carga
#   desired_capacity    = 1      # Capacidade desejada em estado normal
#
#   # Distribuição em múltiplas AZs (alta disponibilidade)
#   vpc_zone_identifier = [
#     aws_subnet.public_a.id,   # sa-east-1a
#     aws_subnet.public_b.id,   # sa-east-1c
#   ]
#
#   # Conecta automaticamente novas instâncias ao Target Group do ALB
#   target_group_arns = [aws_lb_target_group.tg.arn]
#
#   launch_template {
#     id      = aws_launch_template.app_lt.id
#     version = "$Latest"
#   }
#
#   # Health check via ALB (mais robusto que EC2 health check puro)
#   health_check_type         = "ELB"
#   health_check_grace_period = 120  # 2 min para a aplicação inicializar
#
#   # Self-healing: substitui instâncias não saudáveis automaticamente
#   instance_refresh {
#     strategy = "Rolling"
#     preferences {
#       min_healthy_percentage = 50
#     }
#   }
#
#   tag {
#     key                 = "Name"
#     value               = "lacrei-asg-instance"
#     propagate_at_launch = true
#   }
#
#   lifecycle {
#     create_before_destroy = true
#   }
# }


# ── Política de Escalabilidade: escala quando CPU > 70% ──────────────────────
#
# resource "aws_autoscaling_policy" "scale_out_cpu" {
#   name                   = "lacrei-scale-out-cpu"
#   autoscaling_group_name = aws_autoscaling_group.app_asg.name
#   policy_type            = "TargetTrackingScaling"
#
#   target_tracking_configuration {
#     predefined_metric_specification {
#       predefined_metric_type = "ASGAverageCPUUtilization"
#     }
#     target_value = 70.0
#   }
# }
