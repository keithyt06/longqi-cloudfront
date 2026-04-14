output "vpc_origin_security_group_id" {
  description = "VPC Origin 安全组 ID（绑定到 CloudFront VPC Origin ENI）"
  value       = aws_security_group.vpc_origin.id
}

output "alb_security_group_id" {
  description = "ALB 安全组 ID"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "EC2 安全组 ID"
  value       = aws_security_group.ec2.id
}

output "db_security_group_id" {
  description = "数据库安全组 ID"
  value       = aws_security_group.db.id
}
