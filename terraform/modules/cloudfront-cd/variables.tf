# =============================================================================
# CloudFront Continuous Deployment 模块 — 输入变量
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
  description = "CloudFront 价格等级"
  type        = string
  default     = "PriceClass_All"
}

# -----------------------------------------------------------------------------
# Production Distribution 引用
# -----------------------------------------------------------------------------
variable "production_distribution_id" {
  description = "Production CloudFront Distribution ID（用于标签和文档引用）"
  type        = string
  default     = ""
}

variable "production_distribution_arn" {
  description = "Production CloudFront Distribution ARN"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Origin 配置（与 Production 共享）
# -----------------------------------------------------------------------------
variable "s3_bucket_regional_domain_name" {
  description = "S3 桶区域域名"
  type        = string
}

variable "alb_dns_name" {
  description = "Internal ALB DNS 名称"
  type        = string
}

variable "oac_id" {
  description = "S3 Origin Access Control ID（共享 Production 的 OAC）"
  type        = string
}

variable "vpc_origin_id" {
  description = "VPC Origin ID（共享 Production 的 VPC Origin）"
  type        = string
}

# -----------------------------------------------------------------------------
# 缓存策略 ID（从 cloudfront 模块传入）
# -----------------------------------------------------------------------------
variable "product_cache_policy_id" {
  description = "ProductCache 自定义缓存策略 ID"
  type        = string
}

variable "page_cache_policy_id" {
  description = "PageCache 自定义缓存策略 ID"
  type        = string
}

variable "origin_request_policy_id" {
  description = "AllViewerExceptHostHeader ORP ID"
  type        = string
}

# -----------------------------------------------------------------------------
# 安全
# -----------------------------------------------------------------------------
variable "acm_certificate_arn" {
  description = "us-east-1 ACM 证书 ARN"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN（为空则不关联）"
  type        = string
  default     = ""
}

variable "key_group_id" {
  description = "签名 URL Key Group ID（为空则 /premium/* 不要求签名）"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudFront Function
# -----------------------------------------------------------------------------
variable "cf_function_arn" {
  description = "绑定到 Default Behavior 的 CloudFront Function ARN（为空则不绑定）"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# 流量策略
# -----------------------------------------------------------------------------
variable "traffic_config_type" {
  description = "流量分流模式: SingleWeight (按权重) 或 SingleHeader (按 Header)"
  type        = string
  default     = "SingleWeight"

  validation {
    condition     = contains(["SingleWeight", "SingleHeader"], var.traffic_config_type)
    error_message = "traffic_config_type must be SingleWeight or SingleHeader"
  }
}

variable "staging_traffic_weight" {
  description = "SingleWeight 模式下导入 Staging 的流量百分比 (0.0 ~ 0.15)"
  type        = number
  default     = 0.05
}
