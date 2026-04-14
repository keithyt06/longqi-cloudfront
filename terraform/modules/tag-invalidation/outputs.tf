# =============================================================================
# Tag-Based Invalidation 模块 - 输出
# =============================================================================

output "lambda_edge_arn" {
  description = "Lambda@Edge 函数的 qualified ARN（含版本号），用于关联 CloudFront Behavior"
  value       = aws_lambda_function.origin_response.qualified_arn
}

output "lambda_edge_function_name" {
  description = "Lambda@Edge 函数名称"
  value       = aws_lambda_function.origin_response.function_name
}

output "invalidation_lambda_arn" {
  description = "Invalidation Trigger Lambda ARN，供 EC2 IAM Policy 引用"
  value       = aws_lambda_function.invalidation_trigger.arn
}

output "invalidation_lambda_function_name" {
  description = "Invalidation Trigger Lambda 函数名称"
  value       = aws_lambda_function.invalidation_trigger.function_name
}

output "invalidation_lambda_function_url" {
  description = "Invalidation Lambda Function URL，供 Express 通过 HTTP 调用"
  value       = aws_lambda_function_url.invalidation_trigger_url.function_url
}

output "dynamodb_table_name" {
  description = "DynamoDB 表名"
  value       = aws_dynamodb_table.cache_tags.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB 表 ARN"
  value       = aws_dynamodb_table.cache_tags.arn
}

output "step_functions_arn" {
  description = "Step Functions 状态机 ARN（仅 enable_step_functions=true 时有值）"
  value       = var.enable_step_functions ? aws_sfn_state_machine.tag_purge_workflow[0].arn : null
}

output "lambda_edge_role_arn" {
  description = "Lambda@Edge IAM Role ARN"
  value       = aws_iam_role.lambda_edge_role.arn
}

output "invalidation_lambda_role_arn" {
  description = "Invalidation Lambda IAM Role ARN"
  value       = aws_iam_role.invalidation_lambda_role.arn
}
