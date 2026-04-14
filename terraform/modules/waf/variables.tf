# =============================================================================
# WAF 模块 — 输入变量
# =============================================================================

variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

variable "enable_bot_control" {
  description = "是否启用 Bot Control TARGETED 级别（额外费用: $10/月 + $1/百万请求）"
  type        = bool
  default     = false
}

variable "rate_limit" {
  description = "速率限制: 同一 IP 在 5 分钟评估窗口内允许的最大请求数"
  type        = number
  default     = 2000
}

variable "geo_block_countries" {
  description = "要封禁的国家代码列表 (ISO 3166-1 alpha-2)，空列表则不创建 Geo Block 规则"
  type        = list(string)
  default     = ["KP", "IR"]
}
