# =============================================================================
# CloudFront 模块 — 输出
# =============================================================================

output "distribution_id" {
  description = "CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFront Distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "distribution_domain" {
  description = "CloudFront Distribution 域名 (d1234.cloudfront.net)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront Distribution Hosted Zone ID (Route53 ALIAS 用)"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "vpc_origin_id" {
  description = "VPC Origin ID"
  value       = aws_cloudfront_vpc_origin.alb.id
}

output "vpc_origin_arn" {
  description = "VPC Origin ARN"
  value       = aws_cloudfront_vpc_origin.alb.arn
}

output "oac_id" {
  description = "S3 Origin Access Control ID"
  value       = aws_cloudfront_origin_access_control.s3.id
}

output "product_cache_policy_id" {
  description = "ProductCache 自定义缓存策略 ID"
  value       = aws_cloudfront_cache_policy.product_cache.id
}

output "page_cache_policy_id" {
  description = "PageCache 自定义缓存策略 ID"
  value       = aws_cloudfront_cache_policy.page_cache.id
}

output "origin_request_policy_id" {
  description = "AllViewerExceptHostHeader 自定义 ORP ID"
  value       = aws_cloudfront_origin_request_policy.all_viewer_except_host.id
}

output "cf_function_url_rewrite_arn" {
  description = "cf-url-rewrite CloudFront Function ARN"
  value       = aws_cloudfront_function.url_rewrite.arn
}

output "cf_function_ab_test_arn" {
  description = "cf-ab-test CloudFront Function ARN"
  value       = aws_cloudfront_function.ab_test.arn
}

output "cf_function_geo_redirect_arn" {
  description = "cf-geo-redirect CloudFront Function ARN"
  value       = aws_cloudfront_function.geo_redirect.arn
}

output "key_group_id" {
  description = "签名 URL Key Group ID（未启用时为 null）"
  value       = var.enable_signed_url ? aws_cloudfront_key_group.main[0].id : null
}

output "signed_url_private_key_path" {
  description = "签名 URL 私钥本地路径（未启用时为 null）"
  value       = var.enable_signed_url ? local_file.cf_private_key[0].filename : null
}
