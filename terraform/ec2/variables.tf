###############################################################
# Variables
###############################################################

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

variable "key_pair_name" {
  description = "AWS Key Pair name for EC2 SSH access"
  type        = string
}

variable "wireguard_port" {
  description = "UDP port for WireGuard"
  type        = number
  default     = 64203
}

variable "wireguard_network" {
  description = "Internal IP network range for WireGuard tunnel"
  type        = string
  default     = "10.8.0.0/24"
}

variable "root_volume_size" {
  description = "Root volume size (GB)"
  type        = number
  default     = 20
}

variable "admin_ssh_cidr" {
  description = "List of allowed SSH CIDRs (should restrict to your IP)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # ⚠️ Replace with your actual IP!
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
  description = "Security token for WireGuard Client registration API"
  type        = string
  default     = "wg-edge-secret-2026"
}

variable "wg_api_port" {
  description = "HTTP Port for client registration API"
  type        = number
  default     = 5000
}
