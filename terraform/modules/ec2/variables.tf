variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "instance_type" {
  description = "EC2 实例类型"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "EC2 部署的 Private Subnet ID"
  type        = string
}

variable "security_group_ids" {
  description = "EC2 安全组 ID 列表"
  type        = list(string)
}

variable "key_name" {
  description = "SSH 密钥对名称"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "根卷大小 (GB)"
  type        = number
  default     = 20
}

variable "region" {
  description = "AWS 区域"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# =============================================================================
# 应用配置（传入 user_data.sh 模板）
# =============================================================================
variable "db_host" {
  description = "Aurora 写入端点（Aurora 禁用时为空字符串）"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "数据库名称"
  type        = string
  default     = "unice"
}

variable "db_user" {
  description = "数据库用户名"
  type        = string
  default     = "unice_admin"
}

variable "db_password" {
  description = "数据库密码"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID（Cognito 禁用时为空字符串）"
  type        = string
  default     = ""
}

variable "cognito_client_id" {
  description = "Cognito App Client ID（Cognito 禁用时为空字符串）"
  type        = string
  default     = ""
}

variable "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN（用于 IAM 策略）"
  type        = string
  default     = ""
}

variable "enable_cognito" {
  description = "是否启用 Cognito（避免 count 依赖运行时值）"
  type        = bool
  default     = false
}

variable "dynamodb_table_name" {
  description = "DynamoDB UUID 映射表名称"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "DynamoDB UUID 映射表 ARN（用于 IAM 策略）"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 静态资源桶名称"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 静态资源桶 ARN（用于 IAM 策略）"
  type        = string
}
