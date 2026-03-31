###############################################################
# Variables
###############################################################

variable "aws_region" {
  description = "AWS region để deploy"
  type        = string
  default     = "ap-southeast-1" # Singapore — gần VN nhất
}

variable "project_name" {
  description = "Prefix đặt tên tài nguyên"
  type        = string
  default     = "vpn"
}

variable "vpc_id" {
  description = "VPC ID để tạo Security Group"
  type        = string
}

variable "subnet_id" {
  description = "Subnet ID (public subnet) để đặt EC2"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro" # Đủ dùng cho WireGuard
}

variable "key_pair_name" {
  description = "Tên Key Pair AWS để SSH vào EC2"
  type        = string
}

variable "wireguard_port" {
  description = "Port UDP cho WireGuard"
  type        = number
  default     = 64203
}

variable "wireguard_network" {
  description = "Dải địa chỉ IP nội bộ cho tunnel WireGuard"
  type        = string
  default     = "10.8.0.0/24"
}

variable "root_volume_size" {
  description = "Kích thước ổ root (GB)"
  type        = number
  default     = 20
}

variable "admin_ssh_cidr" {
  description = "Danh sách CIDR được phép SSH (nên giới hạn IP của bạn)"
  type        = list(string)
  default     = ["0.0.0.0/0"] # ⚠️ Thay bằng IP thực tế của bạn!
}

variable "common_tags" {
  description = "Tags dùng chung cho tất cả tài nguyên"
  type        = map(string)
  default = {
    Project     = "WireGuard-VPN"
    ManagedBy   = "Terraform"
    Environment = "production"
  }
}
