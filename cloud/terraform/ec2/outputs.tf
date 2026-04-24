output "instance_id" {
  description = "EC2 Instance ID"
  value       = aws_instance.wireguard.id
}

output "public_ip" {
  description = "Elastic IP attach with WireGuard server"
  value       = aws_eip.wireguard.public_ip
}

output "private_ip" {
  description = "Private IP of EC2"
  value       = aws_instance.wireguard.private_ip
}

output "security_group_id" {
  description = "Security Group ID"
  value       = aws_security_group.wireguard.id
}

output "wireguard_endpoint" {
  description = "WireGuard Endpoint (IP:Port)"
  value       = "${aws_eip.wireguard.public_ip}:${var.wireguard_port}"
}

output "api_endpoint" {
  description = "WireGuard Registration API endpoint"
  value       = var.enable_registration_api ? "https://${local.registration_api_host}:${var.registration_api_tls_port}/register" : "Registration API ingress disabled by default."
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret storing the API token"
  value       = aws_secretsmanager_secret.wg_api_token.arn
  sensitive   = true
}
