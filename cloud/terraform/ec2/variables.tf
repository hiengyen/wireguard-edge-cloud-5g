variable "aws_region" {
  description = "AWS region to deploy"
  type        = string
  default     = "ap-southeast-1" # Singapore
}

variable "project_name" {
  description = "Prefix for resource names"
  type        = string
  default     = "vpn"
}

variable "vpc_id" {
  description = "VPC ID for Security Group creation"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID (public subnet) for EC2 placement"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.medium"
}

variable "key_name" {
  description = "Name of the AWS EC2 Key Pair for SSH access (must exist in AWS before applying)"
  type        = string
}

variable "wireguard_port" {
  description = "UDP port for WireGuard"
  type        = number
  default     = 51820
}

variable "wireguard_network" {
  description = "Internal IP network range for WireGuard tunnel"
  type        = string
  default     = "10.8.0.0/24"
}

variable "wireguard_client_cidr" {
  description = "Sample client host route used in examples, monitoring targets, and peer registration"
  type        = string
  default     = "10.8.0.2/32"

  validation {
    condition     = can(regex("/32$", var.wireguard_client_cidr))
    error_message = "wireguard_client_cidr must be a /32 host route for multi-peer WireGuard."
  }
}

variable "root_volume_size" {
  description = "Root volume size (GB)"
  type        = number
  default     = 20
}

variable "admin_ssh_cidr" {
  description = "List of allowed SSH CIDRs (should restrict to your IP)"
  type        = list(string)
  default     = []
}

variable "common_tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project     = "WireGuard-VPN"
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}


variable "grafana_admin_password" {
  description = "Grafana admin password for the monitoring stack"
  type        = string
  sensitive   = true
  default     = "CHANGE_ME_BEFORE_DEPLOYMENT"
}

variable "prometheus_version" {
  description = "Pinned Prometheus image tag"
  type        = string
  default     = "v3.11.2"
}

variable "grafana_version" {
  description = "Pinned Grafana image tag"
  type        = string
  default     = "13.0.1"
}
