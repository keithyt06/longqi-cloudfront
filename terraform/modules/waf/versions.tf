# =============================================================================
# WAF 模块 — Provider 约束
# WAF Web ACL 必须部署在 us-east-1 才能与 CloudFront 关联
# 根模块通过 providers = { aws = aws.us_east_1 } 传入正确区域的 provider
# =============================================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
