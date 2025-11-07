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

variable "project_prefix" {
  description = "Prefix used for naming AWS resources"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "EC2 instance type for application hosts"
  type        = string
  default     = "t2.nano"
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

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ================== SECURITY GROUPS ==================

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

# ================== DATABASE INSTANCE ==================

resource "aws_instance" "database" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_db.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              exec > /var/log/terraform-bootstrap.log 2>&1

              apt-get update -y
              apt-get install -y postgresql postgresql-contrib

              sudo -u postgres psql -c "CREATE USER monitoring_user WITH PASSWORD 'isis2503';"
              sudo -u postgres createdb -O monitoring_user monitoring_db
              echo "host all all 0.0.0.0/0 trust" >> /etc/postgresql/16/main/pg_hba.conf
              echo "listen_addresses='*'" >> /etc/postgresql/16/main/postgresql.conf
              echo "max_connections=2000" >> /etc/postgresql/16/main/postgresql.conf
              systemctl restart postgresql
              EOT

  tags = merge(local.common_tags, {
    Name = "arquitechs-db"
    Role = "database"
  })
}

# ================== INVENTORYING INSTANCES ==================

resource "aws_instance" "inventorying" {
  for_each = toset(["a", "b"])

  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  associate_public_ip_address = true
  vpc_security_group_ids      = [aws_security_group.traffic_django.id, aws_security_group.traffic_ssh.id]

  user_data = <<-EOT
              #!/bin/bash
              exec > /var/log/terraform-bootstrap.log 2>&1

              export DATABASE_HOST=${aws_instance.database.private_ip}
              echo "DATABASE_HOST=${aws_instance.database.private_ip}" >> /etc/environment

              apt-get update -y
              apt-get install -y python3-pip git build-essential libpq-dev python3-dev

              mkdir -p /labs
              cd /labs

              if [ ! -d Sprint2 ]; then
                git clone ${local.repository}
              fi

              cd Sprint2
              git fetch origin ${local.branch}
              git checkout ${local.branch}

              pip3 install --upgrade pip --break-system-packages
              pip3 install -r requirements.txt --break-system-packages

              # Esperar a que la base de datos esté disponible
              until pg_isready -h ${aws_instance.database.private_ip} -p 5432 -U monitoring_user; do
                echo "Esperando que la base de datos esté lista..."
                sleep 5
              done

              # Limpiar base local SQLite (si existe)
              rm -f db.sqlite3

              python3 manage.py makemigrations inventory
              python3 manage.py migrate
              EOT

  tags = merge(local.common_tags, {
    Name = "inventorying-${each.key}"
    Role = "inventorying"
  })

  depends_on = [aws_instance.database]
}

# ================== LOAD BALANCER ==================

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

  tags = merge(local.common_tags, {
    Name = "inventorying-LB"
  })
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

# ================== OUTPUTS ==================

output "load_balancer_dns" {
  description = "DNS name of the Application Load Balancer"
  value       = aws_lb.inventorying_lb.dns_name
}

output "inventorying_public_ips" {
  description = "Public IP addresses for the inventorying service instances"
  value       = { for id, instance in aws_instance.inventorying : id => instance.public_ip }
}

output "inventorying_private_ips" {
  description = "Private IP addresses for the inventorying service instances"
  value       = { for id, instance in aws_instance.inventorying : id => instance.private_ip }
}

output "database_private_ip" {
  description = "Private IP address for the PostgreSQL database instance"
  value       = aws_instance.database.private_ip
}

output "application_url" {
  description = "URL to access the application through the Load Balancer"
  value       = "http://${aws_lb.inventorying_lb.dns_name}"
}
