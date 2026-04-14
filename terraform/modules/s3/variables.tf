variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "bucket_name" {
  description = "S3 桶名称（全局唯一）"
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "CloudFront Distribution ARN（用于 OAC Bucket Policy，为空则不创建策略）"
  type        = string
  default     = ""
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
