output "bucket_id" {
  description = "S3 桶 ID"
  value       = aws_s3_bucket.static.id
}

output "bucket_arn" {
  description = "S3 桶 ARN"
  value       = aws_s3_bucket.static.arn
}

output "bucket_regional_domain_name" {
  description = "S3 桶区域域名（CloudFront S3 Origin 使用）"
  value       = aws_s3_bucket.static.bucket_regional_domain_name
}
