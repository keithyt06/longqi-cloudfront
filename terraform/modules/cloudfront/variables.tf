# =============================================================================
# CloudFront 模块 — 输入变量
# =============================================================================

# -----------------------------------------------------------------------------
# 基础配置
# -----------------------------------------------------------------------------
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

variable "price_class" {
  description = "CloudFront 价格等级 (PriceClass_All / PriceClass_200 / PriceClass_100)"
  type        = string
  default     = "PriceClass_All"
}

# -----------------------------------------------------------------------------
# S3 源站
# -----------------------------------------------------------------------------
variable "s3_bucket_regional_domain_name" {
  description = "S3 桶的区域域名 (bucket.s3.ap-northeast-1.amazonaws.com)"
  type        = string
}

variable "s3_bucket_id" {
  description = "S3 桶 ID（用于 OAC 策略引用）"
  type        = string
}

# -----------------------------------------------------------------------------
# ALB 源站 (VPC Origin)
# -----------------------------------------------------------------------------
variable "alb_dns_name" {
  description = "Internal ALB 的 DNS 名称"
  type        = string
}

variable "alb_arn" {
  description = "Internal ALB 的 ARN（VPC Origin 用于创建 ENI 连接）"
  type        = string
}

# -----------------------------------------------------------------------------
# 域名与证书
# -----------------------------------------------------------------------------
variable "custom_domain" {
  description = "CloudFront 自定义域名 (unice.keithyu.cloud)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "us-east-1 ACM 通配符证书 ARN (*.keithyu.cloud)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (keithyu.cloud)"
  type        = string
}

# -----------------------------------------------------------------------------
# WAF
# -----------------------------------------------------------------------------
variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN（为空则不关联 WAF）"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Feature Flags
# -----------------------------------------------------------------------------
variable "enable_signed_url" {
  description = "是否启用签名 URL（创建 RSA 密钥对和 Key Group）"
  type        = bool
  default     = true
}

variable "enable_geo_restriction" {
  description = "是否启用地理限制"
  type        = bool
  default     = true
}

variable "geo_restriction_type" {
  description = "地理限制类型 (whitelist / blacklist)"
  type        = string
  default     = "blacklist"
}

variable "geo_restriction_locations" {
  description = "地理限制国家代码列表 (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["KP", "IR"]
}

variable "default_cf_function" {
  description = "绑定到 Default Behavior viewer-request 的 CloudFront Function (url-rewrite / ab-test / geo-redirect / none)"
  type        = string
  default     = "url-rewrite"

  validation {
    condition     = contains(["url-rewrite", "ab-test", "geo-redirect", "none"], var.default_cf_function)
    error_message = "default_cf_function must be one of: url-rewrite, ab-test, geo-redirect, none"
  }
}

# -----------------------------------------------------------------------------
# Continuous Deployment
# -----------------------------------------------------------------------------
variable "cd_policy_id" {
  description = "Continuous Deployment Policy ID（为空则不关联 CD 策略）"
  type        = string
  default     = ""
}
