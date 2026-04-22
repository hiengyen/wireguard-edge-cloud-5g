provider "aws" {
  region = var.aws_region
}

###############################################################
# Data Sources
###############################################################

data "aws_ami" "amazon_linux" {
  owners      = ["137112412989"] # Amazon
  most_recent = true

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
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

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-sg"
  })
}

# WireGuard VPN — UDP ingress
resource "aws_vpc_security_group_ingress_rule" "wireguard_udp" {
  security_group_id = aws_security_group.wireguard.id
  description       = "WireGuard VPN"
  from_port         = var.wireguard_port
  to_port           = var.wireguard_port
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wg-udp-ingress"
  })
}

# Registration API — TCP ingress
resource "aws_vpc_security_group_ingress_rule" "wg_api" {
  security_group_id = aws_security_group.wireguard.id
  description       = "WireGuard Registration API"
  from_port         = var.wg_api_port
  to_port           = var.wg_api_port
  ip_protocol       = "tcp"
  cidr_ipv4         = var.wg_api_cidr

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wg-api-ingress"
  })
}

# SSH — limit by admin IP
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.admin_ssh_cidr)

  security_group_id = aws_security_group.wireguard.id
  description       = "SSH from admin IP"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-ssh-ingress"
  })
}

# Allow all outbound traffic
resource "aws_vpc_security_group_egress_rule" "all_outbound" {
  security_group_id = aws_security_group.wireguard.id
  description       = "All outbound traffic"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-all-egress"
  })
}

###############################################################
# Secrets Manager — API Token (never stored in user_data)
###############################################################

resource "aws_secretsmanager_secret" "wg_api_token" {
  name                    = "${var.project_name}/wg-api-token"
  description             = "WireGuard Registration API authentication token"
  recovery_window_in_days = 0 # Allow immediate deletion on terraform destroy

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wg-api-token"
  })
}

resource "aws_secretsmanager_secret_version" "wg_api_token" {
  secret_id     = aws_secretsmanager_secret.wg_api_token.id
  secret_string = var.wg_api_token
}

###############################################################
# IAM Role — EC2 reads from Secrets Manager only
###############################################################

resource "aws_iam_role" "wireguard_ec2" {
  name = "${var.project_name}-wireguard-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-ec2-role"
  })
}

resource "aws_iam_role_policy" "read_wg_api_secret" {
  name = "${var.project_name}-read-wg-api-secret"
  role = aws_iam_role.wireguard_ec2.id

  # Least-privilege: only GetSecretValue on this specific secret
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.wg_api_token.arn
    }]
  })
}

resource "aws_iam_instance_profile" "wireguard_ec2" {
  name = "${var.project_name}-wireguard-ec2-profile"
  role = aws_iam_role.wireguard_ec2.name

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-ec2-profile"
  })
}

###############################################################
# Elastic IP
###############################################################

resource "aws_eip" "wireguard" {
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-wireguard-eip"
  })
}

# Associate EIP to instance explicitly (best practice in v6)
resource "aws_eip_association" "wireguard" {
  instance_id   = aws_instance.wireguard.id
  allocation_id = aws_eip.wireguard.id
}

###############################################################
# EC2 Instance
###############################################################

resource "aws_instance" "wireguard" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.wireguard.id]
  iam_instance_profile   = aws_iam_instance_profile.wireguard_ec2.name

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
  # Token is fetched at boot from Secrets Manager (NOT embedded in user_data)
  user_data_base64 = base64encode(templatefile("${path.module}/user_data.sh", {
    wireguard_port    = var.wireguard_port
    wireguard_network = var.wireguard_network
    wg_api_port       = var.wg_api_port
    secret_id         = aws_secretsmanager_secret.wg_api_token.name
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
