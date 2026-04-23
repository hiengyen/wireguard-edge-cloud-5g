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
  description = "Default client IP/CIDR used in examples and monitoring targets"
  type        = string
  default     = "10.8.0.2/24"
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
  description = "HTTP Port for client registration API"
  type        = number
  default     = 5000
}

variable "wg_api_cidr" {
  description = "CIDR allowed to call the Registration API. Must be restricted to a known source range."
  type        = string
  default     = "127.0.0.1/32"
}

variable "enable_registration_api" {
  description = "Whether to expose the registration API through the instance security group"
  type        = bool
  default     = false
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
  default     = "v2.54.1"
}

variable "grafana_version" {
  description = "Pinned Grafana image tag"
  type        = string
  default     = "11.2.0"
}
