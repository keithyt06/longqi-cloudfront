variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet ID 列表（ALB 需要至少 2 个不同 AZ 的子网）"
  type        = list(string)
}

variable "security_group_ids" {
  description = "ALB 安全组 ID 列表"
  type        = list(string)
}

variable "target_instance_id" {
  description = "EC2 实例 ID（注册到 Target Group）"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
