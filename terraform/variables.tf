# =============================================================================
# General
# =============================================================================
variable "name" {
  description = "资源名称前缀"
  type        = string
  default     = "unice-demo"
}

variable "region" {
  description = "AWS 主区域"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile 名称"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "所有资源的公共标签"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Network
# =============================================================================
variable "vpc_id" {
  description = "现有 VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet ID 列表（至少 2 个，分布在不同 AZ，用于 ALB / EC2 / Aurora）"
  type        = list(string)
}

# =============================================================================
# EC2
# =============================================================================
variable "instance_type" {
  description = "EC2 实例类型"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "EC2 根卷大小 (GB)"
  type        = number
  default     = 20
}

variable "key_name" {
  description = "SSH 密钥对名称"
  type        = string
  default     = "keith-secret"
}

# =============================================================================
# Database
# =============================================================================
variable "db_password" {
  description = "Aurora PostgreSQL master 密码"
  type        = string
  sensitive   = true
}

# =============================================================================
# S3
# =============================================================================
variable "s3_bucket_name" {
  description = "S3 静态资源桶名称（全局唯一）"
  type        = string
}

# =============================================================================
# CloudFront（Part 2 使用，变量预定义）
# =============================================================================
variable "custom_domain" {
  description = "CloudFront 自定义域名 (CNAME)"
  type        = string
  default     = "unice.keithyu.cloud"
}

variable "acm_certificate_arn" {
  description = "us-east-1 的 ACM 通配符证书 ARN（用于 CloudFront）"
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Route53 托管区域名称"
  type        = string
  default     = "keithyu.cloud"
}

variable "price_class" {
  description = "CloudFront 价格等级"
  type        = string
  default     = "PriceClass_200"
}

variable "default_cf_function" {
  description = "绑定到 Default Behavior 的 CloudFront Function (url-rewrite / ab-test / geo-redirect / none)"
  type        = string
  default     = "url-rewrite"
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

# =============================================================================
# WAF（Part 2 使用，变量预定义）
# =============================================================================
variable "waf_rate_limit" {
  description = "WAF 速率限制：同一 IP 每 5 分钟最大请求数"
  type        = number
  default     = 2000
}

variable "waf_geo_block_countries" {
  description = "WAF 地理封禁国家代码列表 (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["KP", "IR"]
}

# =============================================================================
# Continuous Deployment
# =============================================================================
variable "cd_traffic_config_type" {
  description = "流量分流模式: SingleWeight (按权重) 或 SingleHeader (按 Header)"
  type        = string
  default     = "SingleWeight"
}

variable "cd_staging_traffic_weight" {
  description = "SingleWeight 模式下导入 Staging 的流量百分比 (0.0 ~ 0.15)"
  type        = number
  default     = 0.05
}

# =============================================================================
# Feature Flags
# =============================================================================
variable "enable_cloudfront" {
  description = "启用 CloudFront Distribution"
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "启用 WAF 基础规则（Common/Bad Inputs/Rate Limit/IP Reputation）"
  type        = bool
  default     = true
}

variable "enable_waf_bot_control" {
  description = "启用 WAF Bot Control Targeted + JS SDK（额外费用 $10/月 + $1/百万请求）"
  type        = bool
  default     = false
}

variable "enable_signed_url" {
  description = "启用签名 URL/Cookie（Trusted Key Group）"
  type        = bool
  default     = true
}

variable "enable_geo_restriction" {
  description = "启用地理限制"
  type        = bool
  default     = true
}

variable "enable_cognito" {
  description = "启用 Cognito User Pool 用户认证"
  type        = bool
  default     = true
}

variable "enable_aurora" {
  description = "启用 Aurora Serverless v2 PostgreSQL（最低约 $43/月）"
  type        = bool
  default     = true
}

variable "enable_continuous_deployment" {
  description = "启用 CloudFront Continuous Deployment（Staging 分发，有额外费用）"
  type        = bool
  default     = false
}

variable "enable_tag_invalidation" {
  description = "启用基于标签的缓存失效（Lambda@Edge + DynamoDB 映射 + 可选 Step Functions）"
  type        = bool
  default     = false
}

variable "enable_tag_invalidation_step_functions" {
  description = "启用 Step Functions 编排分批失效（URL 数量可能超过 3000 时推荐开启）"
  type        = bool
  default     = false
}

variable "enable_cloudfront_logging" {
  description = "启用 CloudFront Standard Logging（访问日志存储到 S3）"
  type        = bool
  default     = false
}

variable "enable_response_headers_policy" {
  description = "启用 CloudFront Response Headers Policy（安全响应头: HSTS/X-Content-Type-Options 等）"
  type        = bool
  default     = true
}
