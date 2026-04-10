###############################################################
# WireGuard EC2 Server — Terraform Configuration
# Port: 64203/UDP | OS: Ubuntu 22.04 LTS
###############################################################


terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }


  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################
# Data Sources
###############################################################

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

###############################################################
# Security Group
###############################################################

resource "aws_security_group" "wireguard" {
  name        = "${var.project_name}-wireguard-sg"
  description = "Security Group for WireGuard VPN server"
  vpc_id      = var.vpc_id

  # WireGuard VPN — UDP
  ingress {
    description = "WireGuard VPN"
    from_port   = var.wireguard_port
    to_port     = var.wireguard_port
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Registration API — TCP
  ingress {
    description = "WireGuard Registration API"
    from_port   = var.wg_api_port
    to_port     = var.wg_api_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Should restrict IP if possible
  }

  # SSH - limit by admin IP
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.admin_ssh_cidr
  }

  # Allow all outbound traffic
  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-sg"
  })
}

###############################################################
# Elastic IP
###############################################################

resource "aws_eip" "wireguard" {
  instance = aws_instance.wireguard.id
  domain   = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-eip"
  })
}

###############################################################
# EC2 Instance
###############################################################

resource "aws_instance" "wireguard" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.wireguard.id]

  # Enable temporary public IP (before assigning EIP)
  associate_public_ip_address = true

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.common_tags, {
      Name = "${var.project_name}-wireguard-root"
    })
  }

  # User data — automatically install WireGuard on startup
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    wireguard_port    = var.wireguard_port
    wireguard_network = var.wireguard_network
    wg_api_token      = var.wg_api_token
    wg_api_port       = var.wg_api_port
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 required
    http_put_response_hop_limit = 1
  }

  monitoring = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-server"
  })
}
