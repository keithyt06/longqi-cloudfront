# =============================================================================
# WAF 模块 — 输出
# =============================================================================

output "web_acl_arn" {
  description = "WAF Web ACL ARN（关联到 CloudFront Distribution 的 web_acl_id）"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_name" {
  description = "WAF Web ACL 名称"
  value       = aws_wafv2_web_acl.main.name
}
