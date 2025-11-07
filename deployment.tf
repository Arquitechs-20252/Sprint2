# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para laboratorio con Application Load Balancer
# ******************************************************************

variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.micro"
}

provider "aws" {
  region = var.region
}

locals {
  project_name = "arquitechs"
  repository   = "https://github.com/Arquitechs-20252/Sprint2.git"
  branch       = "main"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# === AMI de Ubuntu 24.04 ===
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# === VPC y Subnets por defecto ===
data "aws_vpc" "default" {
  default = true
}
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# === Seguridad ===
resource "aws_security_group" "traffic_django" {
  name        = "traffic-django"
  description = "Allow Django traffic on port 8080"

  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "traffic-django" })
}

resource "aws_security_group" "traffic_lb" {
  name        = "traffic-lb"
  description = "Allow HTTP traffic to Load Balancer"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "traffic-lb" })
}

resource "aws_security_group" "traffic_ssh" {
  name        = "traffic-ssh"
  description = "Allow SSH access"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, { Name = "traffic-ssh" })
}

# === Instancias Django ===
resource "aws_instance" "inventorying" {
  for_each = toset(["a", "b"])

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [
    aws_security_group.traffic_django.id,
    aws_security_group.traffic_ssh.id
  ]

  user_data = <<-EOT
              #!/bin/bash
              set -euxo pipefail
              LOGFILE="/home/ubuntu/setup.log"
              exec > >(tee -a $LOGFILE | logger -t user-data -s 2>/dev/console) 2>&1

              echo "===== STARTING SETUP ====="
              apt-get update -y
              apt-get install -y python3-pip git build-essential libpq-dev python3-dev

              python3 -m pip install --upgrade pip setuptools wheel

              cd /home/ubuntu
              mkdir -p labs
              cd labs

              if [ ! -d Sprint2 ]; then
                git clone ${local.repository}
              fi

              cd Sprint2
              git fetch origin ${local.branch}
              git checkout ${local.branch}

              echo "===== Installing requirements ====="
              pip3 install -r requirements.txt || pip3 install Django==5.1.2

              echo "===== Running migrations ====="
              python3 manage.py makemigrations
              python3 manage.py migrate

              # Crear producto solo en la instancia 'a'
              if [ "${each.key}" = "a" ]; then
                echo "===== Creating initial product ====="
                python3 manage.py shell <<'PYCODE'
from inventory.models import InventoryProduct
InventoryProduct.objects.get_or_create(
    barcode="BC1001",
    defaults={
        "name": "Producto inicial",
        "location": "Bodega Central",
        "quantity": 25
    }
)
print("✅ Producto creado o ya existente: BC1001")
PYCODE
              fi

              echo "===== Starting Django server ====="
              nohup python3 manage.py runserver 0.0.0.0:8080 > /home/ubuntu/django.log 2>&1 &
              echo "===== SETUP COMPLETE ====="
              EOT

  tags = merge(local.common_tags, {
    Name = "inventorying-${each.key}"
    Role = "inventorying"
  })
}

# === Load Balancer ===
resource "aws_lb_target_group" "inventorying_app_group" {
  name     = "inventorying-app-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 2
  }

  tags = merge(local.common_tags, { Name = "inventorying-app-group" })
}

resource "aws_lb_target_group_attachment" "inventorying" {
  for_each = aws_instance.inventorying
  target_group_arn = aws_lb_target_group.inventorying_app_group.arn
  target_id        = each.value.id
  port             = 8080
}

resource "aws_lb" "inventorying_lb" {
  name               = "inventorying-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.traffic_lb.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  tags = merge(local.common_tags, { Name = "inventorying-LB" })
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.inventorying_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inventorying_app_group.arn
  }
}

# === Outputs ===
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.inventorying_lb.dns_name
}

output "inventorying_public_ips" {
  description = "Public IP addresses for the inventorying instances"
  value       = { for id, instance in aws_instance.inventorying : id => instance.public_ip }
}

output "application_url" {
  description = "URL to access the application through the Load Balancer"
  value       = "http://${aws_lb.inventorying_lb.dns_name}"
}
