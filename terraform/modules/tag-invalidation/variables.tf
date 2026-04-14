# =============================================================================
# Tag-Based Invalidation 模块 - 变量定义
# =============================================================================
# 基于标签的精准缓存失效：Lambda@Edge 捕获 Cache-Tag → DynamoDB 存储映射 →
# Invalidation Lambda 按 tag 批量失效
# =============================================================================

variable "name" {
  description = "资源命名前缀"
  type        = string
  default     = "unice"
}

variable "distribution_id" {
  description = "CloudFront Distribution ID，用于调用 CreateInvalidation API"
  type        = string
}

variable "distribution_arn" {
  description = "CloudFront Distribution ARN，用于 IAM 策略"
  type        = string
}

variable "dynamodb_table_name" {
  description = "DynamoDB 表名，存储 tag → URL 映射"
  type        = string
  default     = "unice-cache-tags"
}

variable "tag_header_name" {
  description = "源站响应中的 tag header 名称（小写）"
  type        = string
  default     = "cache-tag"
}

variable "tag_delimiter" {
  description = "多个 tag 之间的分隔符"
  type        = string
  default     = ","
}

variable "tag_ttl_seconds" {
  description = "DynamoDB 中 tag 记录的 TTL（秒），默认 24 小时。设为 0 禁用 TTL"
  type        = number
  default     = 86400
}

variable "enable_step_functions" {
  description = "是否启用 Step Functions 状态机（当失效 URL 数量可能超过 3000 时建议开启）"
  type        = bool
  default     = false
}

variable "invalidation_batch_size" {
  description = "每次 CloudFront CreateInvalidation 的最大路径数（API 限制为 3000）"
  type        = number
  default     = 3000
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
