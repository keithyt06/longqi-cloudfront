output "instance_id" {
  description = "EC2 实例 ID"
  value       = aws_instance.app.id
}

output "instance_private_ip" {
  description = "EC2 实例内网 IP"
  value       = aws_instance.app.private_ip
}

output "instance_availability_zone" {
  description = "EC2 实例可用区"
  value       = aws_instance.app.availability_zone
}

output "iam_role_arn" {
  description = "EC2 IAM Role ARN"
  value       = aws_iam_role.app.arn
}
