###############################################################
# Outputs
###############################################################

output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.wireguard.id
}

output "public_ip" {
  description = "Elastic IP gắn với WireGuard server"
  value       = aws_eip.wireguard.public_ip
}

output "private_ip" {
  description = "Private IP của EC2"
  value       = aws_instance.wireguard.private_ip
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.wireguard.id
}

output "wireguard_endpoint" {
  description = "Endpoint WireGuard đầy đủ (IP:Port)"
  value       = "${aws_eip.wireguard.public_ip}:${var.wireguard_port}"
}

output "ssh_command" {
  description = "Lệnh SSH để kết nối vào server"
  value       = "ssh -i ~/.ssh/${var.key_pair_name}.pem ubuntu@${aws_eip.wireguard.public_ip}"
}
