# ***************** Universidad de los Andes ***********************
# ****** Departamento de Ingeniería de Sistemas y Computación ******
# ********** Arquitectura y diseño de Software - ISIS2503 **********
#
# Infraestructura para laboratorio con Application Load Balancer
#
# Elementos a desplegar en AWS:
# 1. Grupos de seguridad:
#    - traffic-django (puerto 8080)
#    - traffic-lb (puerto 80)
#    - traffic-db (puerto 5432)
#    - traffic-ssh (puerto 22)
#
# 2. Application Load Balancer:
#    - inventorying-LB
#    - Target Group: inventorying-app-group
#
# 3. Instancias EC2:
#    - arquitechs-db (PostgreSQL instalado y configurado)
#    - inventorying-a (Inventorying app instalada)
#    - inventorying-b (Inventorying app instalada)
# ******************************************************************

# Variable. Define la región de AWS donde se desplegará la infraestructura.
variable "region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

# Variable. Define el prefijo usado para nombrar los recursos en AWS.
variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = ""
}

# Variable. Define el tipo de instancia EC2 a usar para las máquinas virtuales.
variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.nano"
}

# Proveedor. Define el proveedor de infraestructura (AWS) y la región.
provider "aws" {
  region = var.region
}

# Variables locales usadas en la configuración de Terraform.
locals {
  project_name = "arquitechs"
  repository   = "https://github.com/Arquitechs-20252/Sprint2.git"
  branch       = "main"

  common_tags = {
    Project   = local.project_name
    ManagedBy = "Terraform"
  }
}

# Data Source. Busca la AMI más reciente de Ubuntu 24.04 usando los filtros especificados.
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

# Data Source. Obtiene la VPC predeterminada
data "aws_vpc" "default" {
  default = true
}

# Data Source. Obtiene las subnets de la VPC predeterminada en diferentes zonas de disponibilidad
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Recurso. Define el grupo de seguridad para el tráfico de Django (8080).
resource "aws_security_group" "traffic_django" {
    name        = "traffic-django"
    description = "Allow application traffic on port 8080"

    ingress {
        description = "HTTP access for service layer"
        from_port   = 8080
        to_port     = 8080
        protocol    = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = merge(local.common_tags, {
        Name = "traffic-services"
    })
}

# Recurso. Define el grupo de seguridad para el tráfico del Load Balancer (80).
resource "aws_security_group" "traffic_lb" {
  name        = "traffic-lb"
  description = "Allow HTTP traffic to Load Balancer"

  ingress {
    description = "HTTP traffic"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "traffic-lb"
  })
}

# Recurso. Define el grupo de seguridad para el tráfico de la base de datos (5432).
resource "aws_security_group" "traffic_db" {
  name        = "traffic-db"
  description = "Allow PostgreSQL access"

  ingress {
    description = "Traffic from anywhere to DB"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "traffic-db"
  })
}

# Recurso. Define el grupo de seguridad para el tráfico SSH (22) y permite todo el tráfico saliente.
resource "aws_security_group" "traffic_ssh" {
  name        = "traffic-ssh"
  description = "Allow SSH access"

  ingress {
    description = "SSH access from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "traffic-ssh"
  })
}

# Recurso. Define la instancia EC2 para la base de datos PostgreSQL.
resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash

              sudo apt-get update -y
              sudo apt-get install -y postgresql postgresql-contrib

              sudo -u postgres psql -c "CREATE USER monitoring_user WITH PASSWORD 'isis2503';"
              sudo -u postgres createdb -O monitoring_user monitoring_db
              echo "host all all 0.0.0.0/0 trust" | sudo tee -a /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              echo "max_connections=2000" | sudo tee -a /etc/postgresql/16/main/postgresql.conf
              sudo service postgresql restart
              EOT

  tags = merge(local.common_tags, {
    Name = "arquitechs-db"
    Role = "database"
  })
}

# Recurso. Define las instancias EC2 para el servicio de inventorying.
# Se crean dos instancias (a, b) usando un bucle.
resource "aws_instance" "inventorying" {
  for_each = toset(["a", "b"])

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              sudo export DATABASE_HOST=${aws_instance.database.private_ip}
              echo "DATABASE_HOST=${aws_instance.database.private_ip}" | sudo tee -a /etc/environment

              sudo apt-get update -y
              sudo apt-get install -y python3-pip git build-essential libpq-dev python3-dev

              mkdir -p /labs
              cd /labs

              if [ ! -d Sprint2 ]; then
                git clone ${local.repository}
              fi

              cd Sprint2
              git fetch origin ${local.branch}
              git checkout ${local.branch}
              sudo pip3 install --upgrade pip --break-system-packages
              sudo pip3 install -r requirements.txt --break-system-packages
              
              sudo python3 manage.py makemigrations
              sudo python3 manage.py migrate
              EOT

  tags = merge(local.common_tags, {
    Name = "inventorying-${each.key}"
    Role = "inventorying"
  })

  depends_on = [aws_instance.database]
}

# Recurso. Define el Target Group para el Application Load Balancer
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

  tags = merge(local.common_tags, {
    Name = "inventorying-app-group"
  })
}

# Recurso. Registra las instancias de inventorying en el Target Group
resource "aws_lb_target_group_attachment" "inventorying" {
  for_each = aws_instance.inventorying

  target_group_arn = aws_lb_target_group.inventorying_app_group.arn
  target_id        = each.value.id
  port             = 8080
}

# Recurso. Define el Application Load Balancer
resource "aws_lb" "inventorying_lb" {
  name               = "inventorying-LB"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.traffic_lb.id]
  subnets            = data.aws_subnets.default.ids

  enable_deletion_protection = false

  tags = merge(local.common_tags, {
    Name = "inventorying-LB"
  })
}

# Recurso. Define el listener del Load Balancer (HTTP puerto 80)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.inventorying_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.inventorying_app_group.arn
  }
}

# Salida. Muestra el DNS del Load Balancer
output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.inventorying_lb.dns_name
}

# Salida. Muestra las direcciones IP públicas de las instancias de inventorying.
output "inventorying_public_ips" {
  description = "Public IP addresses for the inventorying service instances"
  value       = { for id, instance in aws_instance.inventorying : id => instance.public_ip }
}

# Salida. Muestra las direcciones IP privadas de las instancias de inventorying.
output "inventorying_private_ips" {
  description = "Private IP addresses for the inventorying service instances"
  value       = { for id, instance in aws_instance.inventorying : id => instance.private_ip }
}

# Salida. Muestra la dirección IP privada de la instancia de la base de datos PostgreSQL.
output "database_private_ip" {
  description = "Private IP address for the PostgreSQL database instance"
  value       = aws_instance.database.private_ip
}

# Salida. Muestra la URL completa para acceder a la aplicación
output "application_url" {
  description = "URL to access the application through the Load Balancer"
  value       = "http://${aws_lb.inventorying_lb.dns_name}"
}
