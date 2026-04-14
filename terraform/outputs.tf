# =============================================================================
# 根模块输出 — 关键资源 ID / URL / ARN
# =============================================================================

# -----------------------------------------------------------------------------
# 站点访问
# -----------------------------------------------------------------------------
output "site_url" {
  description = "站点 URL"
  value       = var.enable_cloudfront ? "https://${var.custom_domain}" : "N/A (CloudFront disabled)"
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = var.enable_cloudfront ? module.cloudfront[0].distribution_id : null
}

output "cloudfront_distribution_domain" {
  description = "CloudFront Distribution 域名 (d1234.cloudfront.net)"
  value       = var.enable_cloudfront ? module.cloudfront[0].distribution_domain : null
}

# -----------------------------------------------------------------------------
# 源站
# -----------------------------------------------------------------------------
output "alb_dns_name" {
  description = "Internal ALB DNS 名称"
  value       = module.alb.alb_dns_name
}

output "ec2_instance_id" {
  description = "EC2 实例 ID"
  value       = module.ec2.instance_id
}

output "s3_bucket_name" {
  description = "S3 静态内容桶名称"
  value       = module.s3.bucket_id
}

# -----------------------------------------------------------------------------
# 安全
# -----------------------------------------------------------------------------
output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? module.waf[0].web_acl_arn : null
}

output "signed_url_private_key_path" {
  description = "签名 URL 私钥本地路径（EC2 user_data 需要此密钥）"
  value       = var.enable_cloudfront && var.enable_signed_url ? module.cloudfront[0].signed_url_private_key_path : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Continuous Deployment
# -----------------------------------------------------------------------------
output "staging_distribution_id" {
  description = "Staging CloudFront Distribution ID"
  value       = var.enable_continuous_deployment ? module.cloudfront_cd[0].staging_distribution_id : null
}

output "staging_distribution_domain" {
  description = "Staging CloudFront Distribution 域名"
  value       = var.enable_continuous_deployment ? module.cloudfront_cd[0].staging_distribution_domain : null
}

# -----------------------------------------------------------------------------
# 认证
# -----------------------------------------------------------------------------
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = var.enable_cognito ? module.cognito[0].user_pool_id : null
}

# -----------------------------------------------------------------------------
# 数据库
# -----------------------------------------------------------------------------
output "aurora_cluster_endpoint" {
  description = "Aurora Serverless v2 集群端点"
  value       = var.enable_aurora ? module.database[0].aurora_endpoint : null
}

# -----------------------------------------------------------------------------
# Tag-Based Invalidation
# -----------------------------------------------------------------------------
output "tag_invalidation_lambda_edge_arn" {
  description = "Lambda@Edge ARN for Cache-Tag Origin Response"
  value       = var.enable_tag_invalidation && var.enable_cloudfront ? module.tag_invalidation[0].lambda_edge_arn : null
}

output "tag_invalidation_dynamodb_table" {
  description = "DynamoDB table for tag-URL mappings"
  value       = var.enable_tag_invalidation && var.enable_cloudfront ? module.tag_invalidation[0].dynamodb_table_name : null
}

# -----------------------------------------------------------------------------
# 操作提示
# -----------------------------------------------------------------------------
output "next_steps" {
  description = "部署后操作步骤"
  value       = <<-EOT

    ========================================
    CloudFront 全功能演示平台 - 部署完成
    ========================================

    1. 上传静态资源到 S3:
       aws s3 sync ./static/ s3://${module.s3.bucket_id}/ --profile default

    2. 验证站点:
       curl -I https://${var.custom_domain}/api/health

    3. 测试 CloudFront Functions:
       # URL 重写
       curl -v https://${var.custom_domain}/products/1
       # Debug 端点查看注入的 header
       curl https://${var.custom_domain}/api/debug | jq

    4. 测试 WAF:
       # 速率限制测试
       for i in $(seq 1 100); do curl -s -o /dev/null -w "%%{http_code}\n" https://${var.custom_domain}/api/health; done

    5. 测试签名 URL:
       # 直接访问 /premium/* 应返回 403
       curl -I https://${var.custom_domain}/premium/test.pdf

    ${var.enable_continuous_deployment ? "6. Continuous Deployment:\n       # Staging 域名: ${module.cloudfront_cd[0].staging_distribution_domain}\n       # 添加 Header 测试: curl -H 'aws-cf-cd-staging: true' https://${var.custom_domain}/" : ""}
  EOT
}
