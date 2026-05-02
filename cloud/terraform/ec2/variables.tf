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
  default     = "t3.micro"
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

variable "wg_api_token" {
  description = "Security token for WireGuard Client registration API. Must be provided via TF_VAR_wg_api_token or tfvars."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(var.wg_api_token) >= 32
    error_message = "wg_api_token must be at least 32 characters."
  }
}

variable "wg_api_port" {
  description = "Internal localhost port for the registration API application"
  type        = number
  default     = 5000
}

variable "wg_api_cidr" {
  description = "CIDR allowed to call the TLS reverse proxy for the Registration API. Must be restricted to a known source range."
  type        = string
  default     = "127.0.0.1/32"
}

variable "enable_registration_api" {
  description = "Whether to expose the registration API through the instance security group"
  type        = bool
  default     = false
}

variable "registration_api_tls_port" {
  description = "Public TLS port exposed by the reverse proxy in front of the registration API"
  type        = number
  default     = 443
}

variable "registration_api_domain" {
  description = "Optional public hostname or Elastic IP presented by the TLS reverse proxy certificate bootstrap. Leave empty to use the EC2 Elastic IP automatically."
  type        = string
  default     = ""
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
