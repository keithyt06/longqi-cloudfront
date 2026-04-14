# =============================================================================
# Tag-Based Invalidation 模块 - 主配置
# =============================================================================
# 架构参考: https://github.com/aws-samples/amazon-cloudfront-tagbased-invalidations
#
# 组件:
#   1. DynamoDB 表: 存储 tag → URL 映射 (PK=tag, SK=url)
#   2. Lambda@Edge (Origin Response): 解析 Cache-Tag header，写入 DynamoDB
#   3. Lambda (Invalidation Trigger): 按 tag 查询 URL，调用 CloudFront 失效
#   4. Step Functions (可选): 当 URL > 3000 时分批失效
#   5. IAM Role: 各 Lambda 所需权限
#   6. CloudWatch Log Group: 日志收集
# =============================================================================

# -----------------------------------------------------------------------------
# Data Sources
# -----------------------------------------------------------------------------

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

# Lambda@Edge 必须部署在 us-east-1
# 本模块假设通过 provider alias 传入 us-east-1 provider
# 在根模块中: providers = { aws.us_east_1 = aws.us_east_1 }

# -----------------------------------------------------------------------------
# 1. DynamoDB 表: tag → URL 映射
# -----------------------------------------------------------------------------
# PK = tag (如 "product-123", "category-hair")
# SK = url (如 "/api/products/123", "/api/products?category=hair")
# TTL = expire_at (Unix 时间戳，自动清理过期记录)
# -----------------------------------------------------------------------------

resource "aws_dynamodb_table" "cache_tags" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "tag"
  range_key    = "url"

  attribute {
    name = "tag"
    type = "S"
  }

  attribute {
    name = "url"
    type = "S"
  }

  # TTL 自动清理过期的 tag 记录
  # expire_at 为 Unix 时间戳，DynamoDB 会在过期后自动删除
  ttl {
    attribute_name = "expire_at"
    enabled        = var.tag_ttl_seconds > 0
  }

  tags = merge(var.tags, {
    Name    = var.dynamodb_table_name
    Purpose = "CloudFront tag-based cache invalidation"
  })
}

# -----------------------------------------------------------------------------
# 2. Lambda@Edge: Origin Response 处理器
# -----------------------------------------------------------------------------
# 触发时机: CloudFront 从源站收到响应时（仅 Cache Miss 触发）
# 职责:
#   - 解析响应中的 Cache-Tag header
#   - 将每个 tag + URI 写入 DynamoDB
#   - 删除 Cache-Tag header（不暴露给客户端）
#   - 返回清理后的响应
#
# 注意: Lambda@Edge 必须部署在 us-east-1，使用 provider alias
# -----------------------------------------------------------------------------

# Lambda@Edge 的 IAM Role
# 需要 edgelambda.amazonaws.com 和 lambda.amazonaws.com 双重信任
resource "aws_iam_role" "lambda_edge_role" {
  name = "${var.name}-cache-tag-edge-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = [
            "lambda.amazonaws.com",
            "edgelambda.amazonaws.com"
          ]
        }
      }
    ]
  })

  tags = var.tags
}

# Lambda@Edge 需要写入 DynamoDB 的权限
# 注意: Lambda@Edge 在全球边缘节点执行，需要跨区域写 DynamoDB
resource "aws_iam_role_policy" "lambda_edge_dynamodb" {
  name = "${var.name}-cache-tag-edge-dynamodb"
  role = aws_iam_role.lambda_edge_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ]
        Resource = aws_dynamodb_table.cache_tags.arn
      }
    ]
  })
}

# Lambda@Edge 基础日志权限
resource "aws_iam_role_policy_attachment" "lambda_edge_logs" {
  role       = aws_iam_role.lambda_edge_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Lambda@Edge 函数代码打包
data "archive_file" "lambda_edge_zip" {
  type        = "zip"
  output_path = "${path.module}/files/lambda-edge-origin-response.zip"

  source {
    content  = local.lambda_edge_code
    filename = "index.mjs"
  }
}

# Lambda@Edge 函数 (必须部署在 us-east-1)
resource "aws_lambda_function" "origin_response" {
  provider = aws.us_east_1

  function_name = "${var.name}-cache-tag-origin-response"
  description   = "CloudFront Origin Response: 解析 Cache-Tag header 并写入 DynamoDB"
  role          = aws_iam_role.lambda_edge_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 30
  memory_size   = 128
  publish       = true # Lambda@Edge 需要发布版本

  filename         = data.archive_file.lambda_edge_zip.output_path
  source_code_hash = data.archive_file.lambda_edge_zip.output_base64sha256

  tags = merge(var.tags, {
    Name = "${var.name}-cache-tag-origin-response"
  })
}

# Lambda@Edge CloudWatch Log Group (us-east-1)
resource "aws_cloudwatch_log_group" "lambda_edge_logs" {
  provider = aws.us_east_1

  name              = "/aws/lambda/us-east-1.${aws_lambda_function.origin_response.function_name}"
  retention_in_days = 14

  tags = var.tags
}

# Lambda@Edge 代码 (Node.js 20, ESM)
locals {
  lambda_edge_code = <<-NODEJS
// =============================================================================
// Lambda@Edge: Origin Response - Cache Tag 捕获
// =============================================================================
// 触发: CloudFront Origin Response（仅 Cache Miss 时执行）
// 功能: 解析源站响应中的 Cache-Tag header，将 tag → URL 映射写入 DynamoDB
// 运行时: Node.js 20.x (ESM)
// =============================================================================

import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';

// DynamoDB 配置
// Lambda@Edge 在边缘节点运行，显式指定 DynamoDB 所在区域
const DYNAMODB_REGION = '${data.aws_region.current.name}';
const TABLE_NAME = '${var.dynamodb_table_name}';
const TAG_HEADER = '${var.tag_header_name}';
const TAG_DELIMITER = '${var.tag_delimiter}';
const TAG_TTL_SECONDS = ${var.tag_ttl_seconds};

const dynamodb = new DynamoDBClient({ region: DYNAMODB_REGION });

export const handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;

  // 检查响应中是否包含 Cache-Tag header
  const tagHeader = response.headers[TAG_HEADER];
  if (!tagHeader || !tagHeader[0] || !tagHeader[0].value) {
    return response;
  }

  const tagValue = tagHeader[0].value;
  const uri = request.uri;
  const querystring = request.querystring;
  // 完整 URL = URI + QueryString（作为缓存键的一部分）
  const fullUrl = querystring ? uri + '?' + querystring : uri;

  // 解析多个 tag（逗号分隔，去除空白）
  const tags = tagValue.split(TAG_DELIMITER).map(t => t.trim()).filter(t => t.length > 0);

  // 计算 TTL 过期时间（Unix 时间戳）
  const expireAt = TAG_TTL_SECONDS > 0
    ? Math.floor(Date.now() / 1000) + TAG_TTL_SECONDS
    : 0;

  // 并行写入所有 tag → URL 映射到 DynamoDB
  const writePromises = tags.map(tag => {
    const params = {
      TableName: TABLE_NAME,
      Item: {
        tag: { S: tag },
        url: { S: fullUrl },
        uri: { S: uri },
        querystring: { S: querystring || '' },
        updated_at: { S: new Date().toISOString() },
        distribution_id: { S: event.Records[0].cf.config.distributionId },
      },
    };

    // 仅在 TTL > 0 时添加 expire_at 属性
    if (expireAt > 0) {
      params.Item.expire_at = { N: String(expireAt) };
    }

    return dynamodb.send(new PutItemCommand(params));
  });

  try {
    await Promise.all(writePromises);
  } catch (err) {
    // Lambda@Edge 中写入失败不应阻塞响应
    // 错误会记录到 CloudWatch Logs（对应区域）
    console.error('DynamoDB write error:', err);
  }

  // 删除 Cache-Tag header，不暴露给客户端
  delete response.headers[TAG_HEADER];

  return response;
};
NODEJS
}

# -----------------------------------------------------------------------------
# 3. Invalidation Trigger Lambda
# -----------------------------------------------------------------------------
# 触发方式: Express API 调用 (POST /api/admin/invalidate-tag)
# 职责:
#   - 接收 tag 参数
#   - 查询 DynamoDB 获取该 tag 关联的所有 URL
#   - 调用 CloudFront CreateInvalidation API 批量失效
#   - 如果 URL 数量超过 3000，分批提交
# -----------------------------------------------------------------------------

resource "aws_iam_role" "invalidation_lambda_role" {
  name = "${var.name}-cache-tag-invalidation-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# Invalidation Lambda 需要: DynamoDB 读取 + CloudFront 失效 + CloudWatch 日志
resource "aws_iam_role_policy" "invalidation_lambda_policy" {
  name = "${var.name}-cache-tag-invalidation-policy"
  role = aws_iam_role.invalidation_lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBRead"
        Effect = "Allow"
        Action = [
          "dynamodb:Query",
          "dynamodb:GetItem"
        ]
        Resource = [
          aws_dynamodb_table.cache_tags.arn,
          "${aws_dynamodb_table.cache_tags.arn}/index/*"
        ]
      },
      {
        Sid    = "CloudFrontInvalidation"
        Effect = "Allow"
        Action = [
          "cloudfront:CreateInvalidation",
          "cloudfront:ListInvalidations",
          "cloudfront:GetInvalidation"
        ]
        Resource = var.distribution_arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "invalidation_lambda_logs" {
  role       = aws_iam_role.invalidation_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Invalidation Lambda 代码打包
data "archive_file" "invalidation_lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/files/lambda-invalidation-trigger.zip"

  source {
    content  = local.invalidation_lambda_code
    filename = "index.mjs"
  }
}

resource "aws_lambda_function" "invalidation_trigger" {
  function_name = "${var.name}-cache-tag-invalidation"
  description   = "根据 tag 查询 DynamoDB，批量调用 CloudFront CreateInvalidation"
  role          = aws_iam_role.invalidation_lambda_role.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 60
  memory_size   = 256

  filename         = data.archive_file.invalidation_lambda_zip.output_path
  source_code_hash = data.archive_file.invalidation_lambda_zip.output_base64sha256

  environment {
    variables = {
      DYNAMODB_TABLE_NAME     = var.dynamodb_table_name
      DISTRIBUTION_ID         = var.distribution_id
      INVALIDATION_BATCH_SIZE = tostring(var.invalidation_batch_size)
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-cache-tag-invalidation"
  })
}

# Invalidation Lambda CloudWatch Log Group
resource "aws_cloudwatch_log_group" "invalidation_lambda_logs" {
  name              = "/aws/lambda/${aws_lambda_function.invalidation_trigger.function_name}"
  retention_in_days = 14

  tags = var.tags
}

# Lambda Function URL（供 Express 通过 HTTP 直接调用，免去配置 API Gateway）
resource "aws_lambda_function_url" "invalidation_trigger_url" {
  function_name      = aws_lambda_function.invalidation_trigger.function_name
  authorization_type = "AWS_IAM"
}

# Invalidation Lambda 代码 (Node.js 20, ESM)
locals {
  invalidation_lambda_code = <<-NODEJS
// =============================================================================
// Invalidation Trigger Lambda
// =============================================================================
// 触发: 由 Express API 或 Step Functions 调用
// 功能: 接收 tag 列表，查询 DynamoDB 获取关联 URL，调用 CloudFront 批量失效
// 运行时: Node.js 20.x (ESM)
// =============================================================================

import { DynamoDBClient, QueryCommand } from '@aws-sdk/client-dynamodb';
import {
  CloudFrontClient,
  CreateInvalidationCommand,
  ListInvalidationsCommand,
} from '@aws-sdk/client-cloudfront';

const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME;
const DISTRIBUTION_ID = process.env.DISTRIBUTION_ID;
const BATCH_SIZE = parseInt(process.env.INVALIDATION_BATCH_SIZE || '3000', 10);

const dynamodb = new DynamoDBClient({});
const cloudfront = new CloudFrontClient({});

/**
 * 查询单个 tag 关联的所有 URL
 * DynamoDB 使用分页查询，确保获取全部结果
 */
async function getUrlsByTag(tag) {
  const urls = [];
  let lastEvaluatedKey = undefined;

  do {
    const params = {
      TableName: TABLE_NAME,
      KeyConditionExpression: 'tag = :tagValue',
      ExpressionAttributeValues: {
        ':tagValue': { S: tag },
      },
      ProjectionExpression: 'url, uri, querystring',
    };

    if (lastEvaluatedKey) {
      params.ExclusiveStartKey = lastEvaluatedKey;
    }

    const result = await dynamodb.send(new QueryCommand(params));

    if (result.Items) {
      for (const item of result.Items) {
        // url 字段存储完整 URL（含 querystring）
        const url = item.url?.S;
        if (url && !urls.includes(url)) {
          urls.push(url);
        }
      }
    }

    lastEvaluatedKey = result.LastEvaluatedKey;
  } while (lastEvaluatedKey);

  return urls;
}

/**
 * 将 URL 数组分成固定大小的批次
 * CloudFront CreateInvalidation API 每次最多 3000 路径
 */
function chunkArray(arr, size) {
  const chunks = [];
  for (let i = 0; i < arr.length; i += size) {
    chunks.push(arr.slice(i, i + size));
  }
  return chunks;
}

/**
 * 调用 CloudFront CreateInvalidation API
 */
async function createInvalidation(paths) {
  if (paths.length === 0) return null;

  const callerReference = 'tag-invalidation-' + Date.now() + '-' + Math.random().toString(36).slice(2, 8);

  const command = new CreateInvalidationCommand({
    DistributionId: DISTRIBUTION_ID,
    InvalidationBatch: {
      Paths: {
        Quantity: paths.length,
        Items: paths,
      },
      CallerReference: callerReference,
    },
  });

  return cloudfront.send(command);
}

export const handler = async (event) => {
  console.log('Received event:', JSON.stringify(event));

  // 支持多种调用方式: Lambda Function URL / API Gateway / 直接调用
  let body;
  if (event.body) {
    // HTTP 调用（Lambda Function URL / API Gateway）
    body = typeof event.body === 'string' ? JSON.parse(event.body) : event.body;
  } else {
    // 直接调用（SDK / Step Functions）
    body = event;
  }

  const { tags, tag } = body;
  // 支持单个 tag 或 tag 数组
  const tagList = tags || (tag ? [tag] : []);

  if (tagList.length === 0) {
    return {
      statusCode: 400,
      body: JSON.stringify({
        error: 'Missing required parameter: tag or tags',
        usage: '{ "tag": "product-1" } or { "tags": ["product-1", "category-hair"] }',
      }),
    };
  }

  console.log('Processing tags:', tagList);

  // 查询所有 tag 关联的 URL（去重）
  const allUrls = new Set();
  for (const t of tagList) {
    const urls = await getUrlsByTag(t);
    urls.forEach(u => allUrls.add(u));
  }

  const urlList = Array.from(allUrls);
  console.log('Found ' + urlList.length + ' unique URLs to invalidate');

  if (urlList.length === 0) {
    return {
      statusCode: 200,
      body: JSON.stringify({
        message: 'No cached URLs found for the given tags',
        tags: tagList,
        invalidated_count: 0,
      }),
    };
  }

  // 分批失效（每批最多 BATCH_SIZE 条路径）
  const batches = chunkArray(urlList, BATCH_SIZE);
  const results = [];

  for (const batch of batches) {
    try {
      const result = await createInvalidation(batch);
      results.push({
        invalidation_id: result.Invalidation?.Id,
        paths_count: batch.length,
        status: result.Invalidation?.Status,
      });
      console.log('Created invalidation:', result.Invalidation?.Id, 'with', batch.length, 'paths');
    } catch (err) {
      console.error('Invalidation error:', err);
      results.push({
        error: err.message,
        paths_count: batch.length,
      });
    }
  }

  return {
    statusCode: 200,
    body: JSON.stringify({
      message: 'Tag-based invalidation completed',
      tags: tagList,
      total_urls: urlList.length,
      batches: results,
      invalidated_urls: urlList.slice(0, 20), // 返回前 20 条供参考
    }),
  };
};
NODEJS
}

# -----------------------------------------------------------------------------
# 4. Step Functions 状态机 (可选)
# -----------------------------------------------------------------------------
# 当失效 URL 数量可能超过 3000 时，使用 Step Functions 编排分批失效
# 流程: 接收 tag 列表 → 逐 tag 查询 DynamoDB → 收集 URL → 分批失效
# -----------------------------------------------------------------------------

# Step Functions IAM Role
resource "aws_iam_role" "step_functions_role" {
  count = var.enable_step_functions ? 1 : 0

  name = "${var.name}-cache-tag-sfn-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "states.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "step_functions_policy" {
  count = var.enable_step_functions ? 1 : 0

  name = "${var.name}-cache-tag-sfn-policy"
  role = aws_iam_role.step_functions_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DynamoDBQuery"
        Effect = "Allow"
        Action = [
          "dynamodb:Query"
        ]
        Resource = [
          aws_dynamodb_table.cache_tags.arn,
          "${aws_dynamodb_table.cache_tags.arn}/index/*"
        ]
      },
      {
        Sid    = "InvokeLambda"
        Effect = "Allow"
        Action = [
          "lambda:InvokeFunction"
        ]
        Resource = aws_lambda_function.invalidation_trigger.arn
      }
    ]
  })
}

resource "aws_sfn_state_machine" "tag_purge_workflow" {
  count = var.enable_step_functions ? 1 : 0

  name     = "${var.name}-cache-tag-purge-workflow"
  role_arn = aws_iam_role.step_functions_role[0].arn

  definition = jsonencode({
    Comment = "Tag-Based Cache Invalidation Workflow - 分批查询 tag 关联 URL 并调用失效"
    StartAt = "ProcessEachTag"
    States = {
      # 第一步: 对每个 tag 并行查询 DynamoDB
      ProcessEachTag = {
        Type      = "Map"
        ItemsPath = "$.tags"
        ItemSelector = {
          "distributionId.$" = "$$.Execution.Input.distributionId"
          "tag.$"            = "$$.Map.Item.Value"
        }
        MaxConcurrency = 10
        Iterator = {
          StartAt = "QueryDynamoDB"
          States = {
            # 查询单个 tag 的所有 URL
            QueryDynamoDB = {
              Type     = "Task"
              Resource = "arn:aws:states:::aws-sdk:dynamodb:query"
              Parameters = {
                TableName                = var.dynamodb_table_name
                "KeyConditionExpression" = "tag = :tagValue"
                "ExpressionAttributeValues" = {
                  ":tagValue" = {
                    "S.$" = "$.tag"
                  }
                }
                ProjectionExpression = "url, uri, querystring"
              }
              ResultPath = "$.queryResult"
              Next       = "CheckResults"
            }
            # 检查是否有结果
            CheckResults = {
              Type = "Choice"
              Choices = [
                {
                  Variable           = "$.queryResult.Count"
                  NumericGreaterThan = 0
                  Next               = "CollectUrls"
                }
              ]
              Default = "NoUrlsFound"
            }
            # 收集 URL 列表
            CollectUrls = {
              Type = "Pass"
              End  = true
              Parameters = {
                "tag.$"  = "$.tag"
                "urls.$" = "$.queryResult.Items[*].url.S"
              }
            }
            NoUrlsFound = {
              Type = "Pass"
              End  = true
              Result = {
                urls = []
              }
            }
          }
        }
        ResultPath = "$.tagResults"
        Next       = "InvokeInvalidationLambda"
      }
      # 第二步: 调用 Invalidation Lambda 执行批量失效
      InvokeInvalidationLambda = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.invalidation_trigger.arn
          Payload = {
            "tags.$"           = "$$.Execution.Input.tags"
            "distributionId.$" = "$$.Execution.Input.distributionId"
            source             = "step-functions"
          }
        }
        OutputPath = "$.Payload"
        Retry = [
          {
            ErrorEquals = [
              "Lambda.ServiceException",
              "Lambda.AWSLambdaException",
              "Lambda.SdkClientException"
            ]
            IntervalSeconds = 3
            MaxAttempts     = 3
            BackoffRate     = 2
          }
        ]
        End = true
      }
    }
  })

  tags = merge(var.tags, {
    Name = "${var.name}-cache-tag-purge-workflow"
  })
}

# -----------------------------------------------------------------------------
# 5. EC2 调用 Invalidation Lambda 的 IAM 权限
# -----------------------------------------------------------------------------
# Express 应用通过 AWS SDK 直接 invoke Lambda 或调用 Function URL
# 需要在 EC2 的 IAM Role 中添加权限（通过输出值在根模块中配置）
# -----------------------------------------------------------------------------

# 输出 Lambda Function ARN，供根模块添加到 EC2 IAM Policy
