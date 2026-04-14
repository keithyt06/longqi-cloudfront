# =============================================================================
# CloudFront Continuous Deployment 模块 — 输出
# =============================================================================

output "staging_distribution_id" {
  description = "Staging CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.staging.id
}

output "staging_distribution_domain" {
  description = "Staging CloudFront Distribution 域名"
  value       = aws_cloudfront_distribution.staging.domain_name
}

output "cd_policy_id" {
  description = "Continuous Deployment Policy ID（传给 Production Distribution）"
  value       = aws_cloudfront_continuous_deployment_policy.main.id
}

output "cd_policy_etag" {
  description = "Continuous Deployment Policy ETag（promote 操作需要）"
  value       = aws_cloudfront_continuous_deployment_policy.main.etag
}
