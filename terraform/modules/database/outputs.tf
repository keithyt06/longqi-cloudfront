# Aurora 输出（Aurora 禁用时返回空字符串）
output "aurora_endpoint" {
  description = "Aurora 集群写入端点"
  value       = var.enable_aurora ? aws_rds_cluster.aurora[0].endpoint : ""
}

output "aurora_reader_endpoint" {
  description = "Aurora 集群只读端点"
  value       = var.enable_aurora ? aws_rds_cluster.aurora[0].reader_endpoint : ""
}

output "aurora_database_name" {
  description = "Aurora 数据库名称"
  value       = var.enable_aurora ? aws_rds_cluster.aurora[0].database_name : ""
}

# DynamoDB 输出
output "dynamodb_table_name" {
  description = "DynamoDB UUID 映射表名称"
  value       = aws_dynamodb_table.trace_mapping.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB UUID 映射表 ARN"
  value       = aws_dynamodb_table.trace_mapping.arn
}
