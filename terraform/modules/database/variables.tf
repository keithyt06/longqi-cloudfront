variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "region" {
  description = "AWS 区域（用于 VPC Endpoint service_name）"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet ID 列表（Aurora 子网组需要至少 2 个 AZ）"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "数据库安全组 ID"
  type        = string
}

variable "db_password" {
  description = "Aurora PostgreSQL master 密码"
  type        = string
  sensitive   = true
}

variable "enable_aurora" {
  description = "是否创建 Aurora Serverless v2 集群"
  type        = bool
  default     = true
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
