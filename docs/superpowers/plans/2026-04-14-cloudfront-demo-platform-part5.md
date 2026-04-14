# CloudFront 全功能演示平台 - 实施计划 Part 5

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 CloudFront 演示平台新增 Tag-Based Invalidation（基于标签的精准缓存失效）功能，支持通过语义化标签（如 `product-123`、`category-hair`）精确失效相关缓存，替代传统的路径通配符失效方式。

**Architecture:** Lambda@Edge (Origin Response) 拦截源站响应中的 `Cache-Tag` header，将 tag->URL 映射写入 DynamoDB；管理员调用失效 API 时，根据 tag 查询 DynamoDB 获取关联 URL，批量调用 CloudFront CreateInvalidation API。架构参考 [aws-samples/amazon-cloudfront-tagbased-invalidations](https://github.com/aws-samples/amazon-cloudfront-tagbased-invalidations)，简化为适合演示平台的精简版本。

**Tech Stack:** Terraform, AWS Lambda@Edge, DynamoDB, CloudFront Invalidation API, Step Functions (可选), Node.js 20, Express

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

**域名:** `unice.keithyu.cloud` | **区域:** `ap-northeast-1` (东京) + `us-east-1` (Lambda@Edge)

---

## Phase 5: Tag-Based Invalidation (Tasks 19-21)

### 架构概览

```
                    传统失效方式                          标签失效方式
                    ─────────────                        ─────────────
                    POST /invalidation                   POST /api/admin/invalidate-tag
                    Paths: ["/api/products/1",           Body: { "tag": "product-1" }
                            "/api/products?page=1",            │
                            "/api/products?category=hair"]     ▼
                            │                            查询 DynamoDB (tag="product-1")
                            │                                  │
                            ▼                                  ▼
                    CloudFront 逐路径失效              获取所有关联 URL，批量失效

    问题：需要知道每个精确 URL              优势：只需知道语义标签，自动找到所有 URL
    Query String 组合爆炸                  tag 可以是 product-id、category、任意维度
```

### 数据流

```
                                    Tag 注入流程 (Origin Response)
                                    ================================

   用户请求                CloudFront                  Origin (EC2 Express)
   ─────── ──────────────► 缓存未命中 ──────────────► GET /api/products/1
                           (Cache Miss)                      │
                                                             ▼
                                                    响应 + Cache-Tag header:
                                                    "product-1, category-hair, product-list"
                                                             │
                           ◄─────────────────────────────────┘
                           │
                    Lambda@Edge (Origin Response)
                           │
                           ├─ 1. 解析 Cache-Tag header
                           ├─ 2. 每个 tag + URI 写入 DynamoDB
                           ├─ 3. 删除 Cache-Tag header（不暴露给客户端）
                           └─ 4. 返回响应给 CloudFront 缓存
                                   │
                                   ▼
                            DynamoDB: unice-cache-tags
                            ┌────────────────┬─────────────────────┬────────────┐
                            │ tag (PK)       │ url (SK)            │ expire_at  │
                            ├────────────────┼─────────────────────┼────────────┤
                            │ product-1      │ /api/products/1     │ 1713100800 │
                            │ category-hair  │ /api/products/1     │ 1713100800 │
                            │ category-hair  │ /api/products?cat=h │ 1713100800 │
                            │ product-list   │ /api/products       │ 1713100800 │
                            └────────────────┴─────────────────────┴────────────┘


                                    Tag 失效流程 (Admin API)
                                    ================================

   管理员                    Express API                  DynamoDB
   ────── ──────────────►  POST /api/admin/               │
                           invalidate-tag                  │
                           { tag: "product-1" }            │
                                  │                        │
                                  ├── Query(tag="product-1") ──►│
                                  │                        │
                                  │◄── ["/api/products/1", ────┘
                                  │     "/api/products?cat=h"]
                                  │
                                  ▼
                           CloudFront CreateInvalidation
                           Paths: ["/api/products/1",
                                   "/api/products?cat=h"]
                                  │
                                  ▼
                           (如果 URL > 3000，走 Step Functions 分批)
```

---

## 文件结构总览 (Part 5)

```
terraform/
├── modules/
│   └── tag-invalidation/                    # Tag-Based Invalidation 模块
│       ├── main.tf                          #   DynamoDB + Lambda@Edge + Invalidation Lambda + Step Functions + IAM
│       ├── variables.tf                     #   distribution_id, dynamodb_table_name, enable_step_functions
│       └── outputs.tf                       #   lambda_edge_arn, invalidation_lambda_arn, dynamodb_table_name
│
app/
├── routes/
│   ├── products.js                          #   [修改] 添加 Cache-Tag header
│   └── admin.js                             #   [新增] POST /api/admin/invalidate-tag
│
hands-on/                                    # [在 docs/ 下]
└── 12-cloudfront-tag-based-invalidation.md  # Hands-on 文档
```

---

## Task 19: Tag-Based Invalidation Terraform 模块

创建 `terraform/modules/tag-invalidation/` 模块，包含 DynamoDB 表、Lambda@Edge (Origin Response)、Invalidation Trigger Lambda、可选 Step Functions 状态机、IAM Role 和 CloudWatch Log Group。

---

### Step 19.1: 创建 `terraform/modules/tag-invalidation/variables.tf`

- [ ] 创建文件 `terraform/modules/tag-invalidation/variables.tf`

```hcl
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
```

---

### Step 19.2: 创建 `terraform/modules/tag-invalidation/main.tf`

- [ ] 创建文件 `terraform/modules/tag-invalidation/main.tf`

```hcl
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
                "KeyConditionExpression"  = "tag = :tagValue"
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
                  Variable     = "$.queryResult.Count"
                  NumericGreaterThan = 0
                  Next         = "CollectUrls"
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
            "tags.$"          = "$$.Execution.Input.tags"
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
```

---

### Step 19.3: 创建 `terraform/modules/tag-invalidation/outputs.tf`

- [ ] 创建文件 `terraform/modules/tag-invalidation/outputs.tf`

```hcl
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
```

---

### Step 19.4: 在根模块中集成 tag-invalidation 模块

- [ ] 修改 `terraform/variables.tf`，添加 feature flag

在文件末尾追加:

```hcl
# --- Tag-Based Invalidation ---

variable "enable_tag_invalidation" {
  description = "是否启用基于标签的缓存失效功能"
  type        = bool
  default     = false
}

variable "enable_tag_invalidation_step_functions" {
  description = "是否启用 Step Functions 编排分批失效（URL > 3000 时推荐开启）"
  type        = bool
  default     = false
}
```

- [ ] 修改 `terraform/main.tf`，添加模块调用

在模块编排区域追加:

```hcl
# =============================================================================
# Tag-Based Invalidation（Phase 5）
# =============================================================================

module "tag_invalidation" {
  count  = var.enable_tag_invalidation ? 1 : 0
  source = "./modules/tag-invalidation"

  providers = {
    aws.us_east_1 = aws.us_east_1
  }

  name                    = var.name
  distribution_id         = module.cloudfront[0].distribution_id
  distribution_arn        = module.cloudfront[0].distribution_arn
  dynamodb_table_name     = "${var.name}-cache-tags"
  tag_header_name         = "cache-tag"
  tag_delimiter           = ","
  tag_ttl_seconds         = 86400
  enable_step_functions   = var.enable_tag_invalidation_step_functions
  invalidation_batch_size = 3000

  tags = local.common_tags
}
```

- [ ] 修改 `terraform/outputs.tf`，添加输出

```hcl
# --- Tag-Based Invalidation ---

output "tag_invalidation_lambda_edge_arn" {
  description = "Lambda@Edge ARN for Cache-Tag Origin Response"
  value       = var.enable_tag_invalidation ? module.tag_invalidation[0].lambda_edge_arn : null
}

output "tag_invalidation_lambda_arn" {
  description = "Invalidation Trigger Lambda ARN"
  value       = var.enable_tag_invalidation ? module.tag_invalidation[0].invalidation_lambda_arn : null
}

output "tag_invalidation_dynamodb_table" {
  description = "DynamoDB table for tag-URL mappings"
  value       = var.enable_tag_invalidation ? module.tag_invalidation[0].dynamodb_table_name : null
}
```

- [ ] 修改 `terraform/terraform.tfvars.example`，添加示例配置

```hcl
# --- Tag-Based Invalidation ---
# enable_tag_invalidation                 = true   # 启用基于标签的精准缓存失效
# enable_tag_invalidation_step_functions  = false  # 大规模失效时启用 Step Functions
```

---

### Step 19.5: 在 CloudFront Behavior 中关联 Lambda@Edge

- [ ] 修改 `terraform/modules/cloudfront/main.tf`，为需要 tag 失效的 Behavior 添加 Lambda@Edge 关联

在 `/api/products*` 的 ordered_cache_behavior 中添加:

```hcl
    # Tag-Based Invalidation: Lambda@Edge Origin Response
    dynamic "lambda_function_association" {
      for_each = var.lambda_edge_origin_response_arn != null ? [1] : []
      content {
        event_type   = "origin-response"
        lambda_arn   = var.lambda_edge_origin_response_arn
        include_body = false
      }
    }
```

- [ ] 修改 `terraform/modules/cloudfront/variables.tf`，添加变量

```hcl
variable "lambda_edge_origin_response_arn" {
  description = "Lambda@Edge Origin Response 函数 qualified ARN（Tag-Based Invalidation）"
  type        = string
  default     = null
}
```

- [ ] 验证 Terraform 配置: `terraform validate` 和 `terraform plan`

---

## Task 20: Express 集成 + Lambda 代码

修改 Express 应用，在商品 API 响应中添加 `Cache-Tag` header，并新增管理员 API 触发标签失效。

---

### Step 20.1: 修改 `app/routes/products.js` - 添加 Cache-Tag header

- [ ] 在 Part 2A Step 8.1 已创建的 products.js 路由中，修改现有的 GET `/` 和 GET `/:id` 路由处理器，添加 Cache-Tag header。以下代码展示修改后的完整路由（变更部分用注释标记）。

```javascript
// =============================================================================
// GET /:id - 单个商品详情
// =============================================================================
// Cache-Tag 格式: product-{id}, category-{category}
// Lambda@Edge 会拦截此 header 并写入 DynamoDB 的 tag → URL 映射
// =============================================================================

router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    // 查询商品数据（从 Aurora PostgreSQL 或模拟数据）
    const product = await getProductById(id);

    if (!product) {
      return res.status(404).json({ error: 'Product not found' });
    }

    // 构建 Cache-Tag header
    // 格式: product-{id}, category-{category}, product-detail
    // 每个 tag 代表一个失效维度:
    //   - product-{id}: 更新单个商品时失效
    //   - category-{category}: 更新整个分类时失效
    //   - product-detail: 全局失效所有商品详情
    const cacheTags = [
      `product-${id}`,
      product.category ? `category-${product.category}` : null,
      'product-detail',
    ].filter(Boolean).join(', ');

    res.set('Cache-Tag', cacheTags);

    // 设置 Cache-Control 供 CloudFront 缓存
    res.set('Cache-Control', 'public, max-age=3600, s-maxage=3600');

    res.json({
      product,
      _meta: {
        cache_tags: cacheTags,
        cached_at: new Date().toISOString(),
      },
    });
  } catch (err) {
    console.error('Error fetching product:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});
```

- [ ] 修改 `app/routes/products.js`，在 GET `/` 列表响应中添加 Cache-Tag header

```javascript
// =============================================================================
// GET / - 商品列表
// =============================================================================
// Cache-Tag 格式: product-list, category-{category}
// 支持 Query String: ?page=1&category=hair&sort=price
// =============================================================================

router.get('/', async (req, res) => {
  try {
    const { page = 1, category, sort } = req.query;

    // 查询商品列表
    const products = await getProducts({ page: parseInt(page), category, sort });

    // 构建 Cache-Tag header
    // 商品列表的 tag 包含:
    //   - product-list: 任何商品变更时可失效整个列表
    //   - category-{category}: 按分类失效（如果指定了分类筛选）
    //   - 每个商品的 product-{id}: 单个商品更新时也能失效包含它的列表
    const cacheTags = ['product-list'];

    if (category) {
      cacheTags.push(`category-${category}`);
    }

    // 为列表中的每个商品添加 tag（最多前 20 个，避免 header 过长）
    products.items.slice(0, 20).forEach(p => {
      cacheTags.push(`product-${p.id}`);
    });

    res.set('Cache-Tag', cacheTags.join(', '));

    // 设置 Cache-Control
    res.set('Cache-Control', 'public, max-age=3600, s-maxage=3600');

    res.json({
      products: products.items,
      pagination: {
        page: parseInt(page),
        total: products.total,
        per_page: products.per_page,
      },
      _meta: {
        cache_tags: cacheTags.join(', '),
        cached_at: new Date().toISOString(),
      },
    });
  } catch (err) {
    console.error('Error fetching products:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});
```

---

### Step 20.2: 创建 `app/routes/admin.js` - 管理员失效 API

- [ ] 创建文件 `app/routes/admin.js`

```javascript
// =============================================================================
// 管理员 API - Tag-Based Cache Invalidation
// =============================================================================
// 所有管理端点需要 JWT 认证（通过 Cognito），防止未授权的缓存失效操作。
//
// POST /api/admin/invalidate-tag   - 按标签失效缓存
// GET  /api/admin/cache-tags       - 查看 DynamoDB 中的 tag 映射
// GET  /api/admin/invalidation-status - 查看 CloudFront 失效状态
// =============================================================================

const express = require('express');
const router = express.Router();
const { requireAuth } = require('../middleware/cognito-auth');
const {
  LambdaClient,
  InvokeCommand,
} = require('@aws-sdk/client-lambda');
const {
  DynamoDBClient,
  QueryCommand,
  ScanCommand,
} = require('@aws-sdk/client-dynamodb');
const {
  CloudFrontClient,
  ListInvalidationsCommand,
} = require('@aws-sdk/client-cloudfront');
const {
  SFNClient,
  StartExecutionCommand,
} = require('@aws-sdk/client-sfn');

// 从环境变量读取配置
const INVALIDATION_LAMBDA_NAME = process.env.INVALIDATION_LAMBDA_NAME || 'unice-cache-tag-invalidation';
const DYNAMODB_TABLE_NAME = process.env.CACHE_TAGS_TABLE_NAME || 'unice-cache-tags';
const DISTRIBUTION_ID = process.env.CLOUDFRONT_DISTRIBUTION_ID || '';
const STEP_FUNCTIONS_ARN = process.env.TAG_INVALIDATION_SFN_ARN || '';
const AWS_REGION = process.env.AWS_REGION || 'ap-northeast-1';

const lambda = new LambdaClient({ region: AWS_REGION });
const dynamodb = new DynamoDBClient({ region: AWS_REGION });
const cloudfront = new CloudFrontClient({ region: AWS_REGION });
const sfn = new SFNClient({ region: AWS_REGION });

// =============================================================================
// POST /api/admin/invalidate-tag
// =============================================================================
// 请求体:
//   { "tag": "product-123" }              - 单个 tag
//   { "tags": ["product-123", "category-hair"] } - 多个 tag
//   { "tag": "product-123", "use_step_functions": true } - 走 Step Functions
//
// 响应:
//   {
//     "message": "Tag-based invalidation completed",
//     "tags": ["product-123"],
//     "total_urls": 5,
//     "batches": [{ "invalidation_id": "I12345", "paths_count": 5, "status": "InProgress" }]
//   }
// =============================================================================

router.post('/api/admin/invalidate-tag', requireAuth, async (req, res) => {
  try {
    const { tag, tags, use_step_functions = false } = req.body;

    // 参数校验
    const tagList = tags || (tag ? [tag] : []);
    if (tagList.length === 0) {
      return res.status(400).json({
        error: '缺少必要参数: tag 或 tags',
        usage: {
          single: '{ "tag": "product-123" }',
          multiple: '{ "tags": ["product-123", "category-hair"] }',
          step_functions: '{ "tag": "product-123", "use_step_functions": true }',
        },
      });
    }

    console.log(`[Admin] Tag invalidation requested: ${tagList.join(', ')}`);

    // 方式一: 使用 Step Functions（适合大量 URL）
    if (use_step_functions && STEP_FUNCTIONS_ARN) {
      const sfnInput = {
        distributionId: DISTRIBUTION_ID,
        tags: tagList,
      };

      const command = new StartExecutionCommand({
        stateMachineArn: STEP_FUNCTIONS_ARN,
        input: JSON.stringify(sfnInput),
        name: `tag-invalidation-${Date.now()}`,
      });

      const result = await sfn.send(command);

      return res.json({
        message: 'Step Functions workflow started',
        execution_arn: result.executionArn,
        start_date: result.startDate,
        tags: tagList,
        mode: 'step-functions',
      });
    }

    // 方式二: 直接调用 Invalidation Lambda（适合少量 URL）
    const payload = JSON.stringify({ tags: tagList });

    const command = new InvokeCommand({
      FunctionName: INVALIDATION_LAMBDA_NAME,
      InvocationType: 'RequestResponse', // 同步调用
      Payload: Buffer.from(payload),
    });

    const lambdaResult = await lambda.send(command);
    const responsePayload = JSON.parse(
      Buffer.from(lambdaResult.Payload).toString()
    );

    // Lambda 返回的 body 是 JSON 字符串，需要再解析一次
    const lambdaBody = typeof responsePayload.body === 'string'
      ? JSON.parse(responsePayload.body)
      : responsePayload;

    res.json({
      ...lambdaBody,
      mode: 'direct-lambda',
    });
  } catch (err) {
    console.error('[Admin] Tag invalidation error:', err);
    res.status(500).json({
      error: '标签失效请求失败',
      message: err.message,
    });
  }
});

// =============================================================================
// GET /api/admin/cache-tags
// =============================================================================
// 查看 DynamoDB 中存储的 tag → URL 映射
// Query String:
//   ?tag=product-123    查看特定 tag 的映射
//   ?limit=50           限制返回数量（默认 50）
// =============================================================================

router.get('/api/admin/cache-tags', requireAuth, async (req, res) => {
  try {
    const { tag, limit = 50 } = req.query;

    if (tag) {
      // 查询特定 tag 的所有 URL
      const command = new QueryCommand({
        TableName: DYNAMODB_TABLE_NAME,
        KeyConditionExpression: 'tag = :tagValue',
        ExpressionAttributeValues: {
          ':tagValue': { S: tag },
        },
        Limit: parseInt(limit),
      });

      const result = await dynamodb.send(command);

      const items = (result.Items || []).map(item => ({
        tag: item.tag?.S,
        url: item.url?.S,
        uri: item.uri?.S,
        querystring: item.querystring?.S,
        updated_at: item.updated_at?.S,
        expire_at: item.expire_at?.N ? new Date(parseInt(item.expire_at.N) * 1000).toISOString() : null,
      }));

      return res.json({
        tag,
        count: result.Count,
        items,
      });
    }

    // 扫描所有 tag（仅用于调试，生产中不推荐 Scan）
    const command = new ScanCommand({
      TableName: DYNAMODB_TABLE_NAME,
      Limit: parseInt(limit),
    });

    const result = await dynamodb.send(command);

    // 按 tag 分组
    const grouped = {};
    (result.Items || []).forEach(item => {
      const tagName = item.tag?.S || 'unknown';
      if (!grouped[tagName]) {
        grouped[tagName] = [];
      }
      grouped[tagName].push({
        url: item.url?.S,
        updated_at: item.updated_at?.S,
        expire_at: item.expire_at?.N ? new Date(parseInt(item.expire_at.N) * 1000).toISOString() : null,
      });
    });

    res.json({
      total_scanned: result.ScannedCount,
      tags: grouped,
    });
  } catch (err) {
    console.error('[Admin] Cache tags query error:', err);
    res.status(500).json({
      error: '查询缓存标签失败',
      message: err.message,
    });
  }
});

// =============================================================================
// GET /api/admin/invalidation-status
// =============================================================================
// 查看 CloudFront 最近的失效请求状态
// Query String: ?limit=10 (默认 10)
// =============================================================================

router.get('/api/admin/invalidation-status', requireAuth, async (req, res) => {
  try {
    const { limit = 10 } = req.query;

    if (!DISTRIBUTION_ID) {
      return res.status(400).json({
        error: '未配置 CLOUDFRONT_DISTRIBUTION_ID 环境变量',
      });
    }

    const command = new ListInvalidationsCommand({
      DistributionId: DISTRIBUTION_ID,
      MaxItems: parseInt(limit),
    });

    const result = await cloudfront.send(command);

    const invalidations = (result.InvalidationList?.Items || []).map(item => ({
      id: item.Id,
      status: item.Status,
      create_time: item.CreateTime,
    }));

    res.json({
      distribution_id: DISTRIBUTION_ID,
      total: result.InvalidationList?.Quantity,
      invalidations,
    });
  } catch (err) {
    console.error('[Admin] Invalidation status error:', err);
    res.status(500).json({
      error: '查询失效状态失败',
      message: err.message,
    });
  }
});

module.exports = router;
```

---

### Step 20.3: 在 Express 主入口注册 admin 路由

- [ ] 修改 `app/server.js`，注册 admin 路由

在现有路由注册之后添加:

```javascript
// 管理员路由 - Tag-Based Cache Invalidation
const adminRoutes = require('./routes/admin');
app.use(adminRoutes);
```

---

### Step 20.4: 更新 Express 依赖

- [ ] 修改 `app/package.json`，确保包含所需的 AWS SDK 依赖

在 dependencies 中添加或确认:

```json
{
  "dependencies": {
    "@aws-sdk/client-lambda": "^3.500.0",
    "@aws-sdk/client-dynamodb": "^3.500.0",
    "@aws-sdk/client-cloudfront": "^3.500.0",
    "@aws-sdk/client-sfn": "^3.500.0"
  }
}
```

- [ ] 运行 `npm install` 安装新依赖

---

### Step 20.5: Lambda@Edge Origin Response 代码详细说明

Lambda@Edge 代码已在 Step 19.2 中通过 Terraform `locals` 内联定义（`local.lambda_edge_code`）。以下补充关键实现说明:

- [ ] 确认 Lambda@Edge 代码符合 CloudFront Origin Response 事件格式

**事件格式参考** (Lambda@Edge Origin Response):

```json
{
  "Records": [
    {
      "cf": {
        "config": {
          "distributionDomainName": "d111111abcdef8.cloudfront.net",
          "distributionId": "EDFDVBD6EXAMPLE",
          "eventType": "origin-response",
          "requestId": "4TyzHTaYWb1GX1qTfsHhEqV6HUDd_BzoBZnwfnvQc_1zF5aciVMo=="
        },
        "request": {
          "clientIp": "203.0.113.178",
          "headers": {},
          "method": "GET",
          "querystring": "category=hair&page=1",
          "uri": "/api/products"
        },
        "response": {
          "headers": {
            "cache-tag": [
              {
                "key": "Cache-Tag",
                "value": "product-list, category-hair, product-1, product-2"
              }
            ],
            "cache-control": [
              {
                "key": "Cache-Control",
                "value": "public, max-age=3600"
              }
            ]
          },
          "status": "200",
          "statusDescription": "OK"
        }
      }
    }
  ]
}
```

- [ ] 确认代码处理以下边界情况:
  - 响应中没有 `Cache-Tag` header 时直接返回（不写 DynamoDB）
  - 源站返回 4xx/5xx 错误时仍会触发（Lambda@Edge Origin Response 的行为），但 Cache-Tag 通常不会出现在错误响应中
  - DynamoDB 写入失败时不阻塞响应（catch error 后继续返回）
  - 多个 tag 之间用逗号分隔，每个 tag 两端的空白被 trim
  - querystring 为空时 fullUrl 不包含 `?`

---

### Step 20.6: Invalidation Trigger Lambda 代码详细说明

Invalidation Trigger Lambda 代码已在 Step 19.2 中通过 Terraform `locals` 内联定义（`local.invalidation_lambda_code`）。以下补充关键实现说明:

- [ ] 确认 Lambda 代码支持以下调用方式:

**直接调用 (SDK InvokeCommand)**:

```json
{
  "tag": "product-123"
}
```

**Lambda Function URL (HTTP POST)**:

```json
POST https://<function-url-id>.lambda-url.ap-northeast-1.on.aws/
Content-Type: application/json

{
  "tags": ["product-123", "category-hair"]
}
```

**Step Functions 调用**:

```json
{
  "tags": ["product-123"],
  "distributionId": "E1EXAMPLE",
  "source": "step-functions"
}
```

- [ ] 确认分批逻辑:
  - CloudFront CreateInvalidation API 限制: 每次最多 3000 路径
  - 代码使用 `chunkArray()` 将 URL 分成每批最多 3000 条
  - 每批独立提交，一批失败不影响其他批次
  - `CallerReference` 使用时间戳 + 随机字符串确保唯一

- [ ] 确认 DynamoDB 查询使用分页:
  - 使用 `LastEvaluatedKey` 循环查询，确保获取 tag 下的全部 URL
  - URL 去重（同一 URL 可能出现在多个 tag 查询结果中）

---

## Task 21: Hands-on 文档 12

编写 Tag-Based Cache Invalidation 的 Hands-on 实操文档，包含传统失效对比、架构说明、Console 操作步骤和验证方法。

---

### Step 21.1: 创建 `hands-on/12-cloudfront-tag-based-invalidation.md`

- [ ] 创建文件 `hands-on/12-cloudfront-tag-based-invalidation.md`

```markdown
# 12 - CloudFront Tag-Based Cache Invalidation: 基于标签的精准缓存失效

> **目标**: 配置 Lambda@Edge + DynamoDB 实现基于语义标签的缓存失效，替代传统的路径通配符失效方式。当商品数据更新时，只需指定标签（如 `product-123`），系统自动找到所有关联的缓存路径并失效。
>
> **预计时间**: 45-60 分钟
>
> **前提条件**:
> - 已创建 CloudFront Distribution（参考 Hands-on 01）
> - 已配置 Cache Behavior（参考 Hands-on 02）
> - 已部署 Express 应用（/api/products 接口正常工作）
> - 具备 Lambda@Edge 部署经验（了解 us-east-1 部署要求）
> - IAM 权限: Lambda、DynamoDB、CloudFront 管理权限

---

## 传统失效 vs 标签失效

### 问题场景

假设商品 ID=123（分类: hair）更新了价格。需要失效的缓存路径包括:

| 缓存路径 | 说明 |
|----------|------|
| `/api/products/123` | 商品详情 API |
| `/api/products?page=1` | 包含该商品的列表第 1 页 |
| `/api/products?page=1&category=hair` | 分类筛选页 |
| `/api/products?category=hair&sort=price` | 分类 + 排序 |
| `/api/products?page=2&category=hair&sort=price` | 分类 + 排序 + 分页 |
| `/products/123` | 商品详情 SSR 页面 |
| ... | Query String 组合可能有数十种 |

### 对比

| 维度 | 传统路径失效 | 标签失效 |
|------|------------|---------|
| **失效方式** | 指定精确路径或通配符 `/*` | 指定语义标签 `product-123` |
| **精确度** | 通配符 `/*` 会清除所有缓存；精确路径需列举每个 URL | 只清除与标签关联的 URL，其他缓存不受影响 |
| **Query String** | 每种 Query String 组合是独立的缓存键，需逐一列举 | 自动追踪所有 Query String 变体 |
| **维护成本** | 需要应用层维护 URL→缓存路径映射 | tag 映射自动维护（Lambda@Edge 写入 DynamoDB） |
| **API 调用** | 1 次 CreateInvalidation + 列举所有路径 | 1 次 API 调用 + 自动查询 DynamoDB |
| **适用场景** | 路径少、Query String 简单的静态站 | 动态 API、Query String 组合多的电商/内容站 |
| **CloudFront 限制** | 每次失效最多 3000 路径，每月 1000 次免费 | 相同，但路径自动发现，不怕遗漏 |

### 标签失效优势示例

```
传统方式（需要知道每个精确路径）:
POST /cloudfront/2020-05-31/distribution/E1EXAMPLE/invalidation
Paths: [
  "/api/products/123",
  "/api/products?page=1",
  "/api/products?page=1&category=hair",
  "/api/products?category=hair&sort=price",
  "/api/products?page=2&category=hair&sort=price",
  ... (可能还有几十条)
]

标签方式（只需知道语义标签）:
POST /api/admin/invalidate-tag
{ "tag": "product-123" }
→ 系统自动找到所有关联 URL 并失效
```

---

## 架构图

```
                    ┌──────────────────────────────────────────────────────┐
                    │                 CloudFront Distribution              │
                    │               unice.keithyu.cloud                   │
                    │                                                      │
                    │  Behavior: /api/products*                            │
                    │    ├─ Cache Policy: ProductCache (3600s)             │
                    │    └─ Lambda@Edge: Origin Response                   │
                    │         ↓ (仅 Cache Miss 触发)                       │
                    └──────────┬──────────────────────────┬────────────────┘
                               │                          │
                    ┌──────────▼──────────┐    ┌──────────▼──────────┐
                    │  VPC Origin → ALB   │    │  Lambda@Edge        │
                    │  → EC2 Express      │    │  Origin Response    │
                    │                     │    │                     │
                    │  响应 headers:       │    │  1. 解析 Cache-Tag  │
                    │  Cache-Tag:         │    │  2. 写入 DynamoDB   │
                    │    product-123,     │    │  3. 删除 header     │
                    │    category-hair    │    │  4. 返回响应        │
                    └─────────────────────┘    └──────────┬──────────┘
                                                          │
                                               ┌──────────▼──────────┐
                                               │     DynamoDB        │
                                               │  unice-cache-tags   │
                                               │                     │
                                               │  PK: tag            │
                                               │  SK: url            │
                                               │  TTL: expire_at     │
                                               └──────────┬──────────┘
                                                          │
                          ┌───────────────────────────────┘
                          │ 管理员触发失效
                          │
               ┌──────────▼──────────┐
               │  POST /api/admin/   │
               │  invalidate-tag     │
               │  { tag: "product-   │
               │    123" }           │
               └──────────┬──────────┘
                          │
               ┌──────────▼──────────┐
               │  Invalidation       │
               │  Lambda             │
               │                     │
               │  1. Query DynamoDB  │
               │     (tag=product-   │
               │      123)           │
               │  2. 收集所有 URL    │
               │  3. CloudFront      │
               │     CreateInvali-   │
               │     dation          │
               └─────────────────────┘
```

---

## 步骤 1: 创建 DynamoDB 表

DynamoDB 表存储 tag → URL 的映射关系。每个缓存的 URL 可能关联多个 tag，每个 tag 下可能有多个 URL。

- [ ] 打开 **DynamoDB Console** → 点击 **Create table**
- [ ] 填写表配置:

| 参数 | 值 |
|------|-----|
| Table name | `unice-cache-tags` |
| Partition key | `tag` (String) |
| Sort key | `url` (String) |

- [ ] 展开 **Table settings** → 选择 **Customize settings**
- [ ] **Read/write capacity settings**: 选择 **On-demand**（按需模式，适合演示环境的不规则流量）
- [ ] 点击 **Create table**

### 启用 TTL

- [ ] 等待表状态变为 **Active**
- [ ] 点击表名进入详情 → 选择 **Additional settings** 标签页
- [ ] 在 **Time to Live (TTL)** 区域点击 **Turn on**
- [ ] TTL attribute 填写: `expire_at`
- [ ] 点击 **Turn on TTL**

> **说明**: TTL 启用后，DynamoDB 会自动删除 `expire_at` 时间戳过期的记录。通常在过期后 48 小时内删除（不是精确即时删除）。这能防止 tag 映射表无限增长。

---

## 步骤 2: 创建 Lambda@Edge 函数（Origin Response）

Lambda@Edge 必须部署在 **us-east-1** 区域。

- [ ] 切换到 **US East (N. Virginia) us-east-1** 区域
- [ ] 打开 **Lambda Console** → 点击 **Create function**
- [ ] 选择 **Author from scratch**
- [ ] 填写配置:

| 参数 | 值 |
|------|-----|
| Function name | `unice-cache-tag-origin-response` |
| Runtime | **Node.js 20.x** |
| Architecture | **x86_64**（Lambda@Edge 要求） |

- [ ] 展开 **Change default execution role** → 选择 **Create a new role with basic Lambda permissions**
- [ ] 点击 **Create function**

### 配置 IAM 权限

- [ ] 进入函数详情 → **Configuration** → **Permissions**
- [ ] 点击 Role name 链接（打开 IAM Console）
- [ ] 在 **Trust relationships** 标签页，点击 **Edit trust policy**
- [ ] 将信任策略修改为:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

- [ ] 点击 **Update policy**

- [ ] 在 **Permissions** 标签页，点击 **Add permissions** → **Create inline policy**
- [ ] 选择 **JSON** 编辑器，粘贴:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:YOUR_ACCOUNT_ID:table/unice-cache-tags"
    }
  ]
}
```

> **注意**: 将 `YOUR_ACCOUNT_ID` 替换为你的 AWS 账号 ID。DynamoDB 表在 ap-northeast-1，但 Lambda@Edge 可以跨区域写入。

- [ ] Policy name 填写 `unice-cache-tag-dynamodb-write`
- [ ] 点击 **Create policy**

### 编写函数代码

- [ ] 返回 Lambda 函数 → **Code** 标签页
- [ ] 将默认文件重命名为 `index.mjs`（ESM 模块）
- [ ] 粘贴以下代码:

```javascript
// Lambda@Edge: Origin Response - Cache Tag 捕获
// 部署区域: us-east-1
// 触发: CloudFront Origin Response (仅 Cache Miss)

import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';

// 配置 - 根据实际环境修改
const DYNAMODB_REGION = 'ap-northeast-1';
const TABLE_NAME = 'unice-cache-tags';
const TAG_HEADER = 'cache-tag';
const TAG_DELIMITER = ',';
const TAG_TTL_SECONDS = 86400; // 24 小时

const dynamodb = new DynamoDBClient({ region: DYNAMODB_REGION });

export const handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;

  // 检查是否有 Cache-Tag header
  const tagHeader = response.headers[TAG_HEADER];
  if (!tagHeader || !tagHeader[0] || !tagHeader[0].value) {
    return response;
  }

  const tagValue = tagHeader[0].value;
  const uri = request.uri;
  const querystring = request.querystring;
  const fullUrl = querystring ? `${uri}?${querystring}` : uri;

  // 解析 tag 列表
  const tags = tagValue.split(TAG_DELIMITER).map(t => t.trim()).filter(t => t.length > 0);

  // 计算 TTL
  const expireAt = TAG_TTL_SECONDS > 0
    ? Math.floor(Date.now() / 1000) + TAG_TTL_SECONDS
    : 0;

  // 并行写入 DynamoDB
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
    if (expireAt > 0) {
      params.Item.expire_at = { N: String(expireAt) };
    }
    return dynamodb.send(new PutItemCommand(params));
  });

  try {
    await Promise.all(writePromises);
  } catch (err) {
    console.error('DynamoDB write error:', err);
    // 不阻塞响应
  }

  // 删除 tag header，不暴露给客户端
  delete response.headers[TAG_HEADER];

  return response;
};
```

- [ ] 点击 **Deploy**

### 配置函数属性

- [ ] **Configuration** → **General configuration** → **Edit**

| 参数 | 值 |
|------|-----|
| Memory | **128 MB** |
| Timeout | **30 seconds**（Lambda@Edge 最大 30 秒） |

- [ ] 点击 **Save**

### 发布版本

Lambda@Edge 必须使用已发布的版本（不能使用 $LATEST）。

- [ ] **Actions** → **Publish new version**
- [ ] Description 填写: `v1 - Initial release`
- [ ] 点击 **Publish**
- [ ] 记录版本 ARN，格式: `arn:aws:lambda:us-east-1:ACCOUNT_ID:function:unice-cache-tag-origin-response:1`

---

## 步骤 3: 在 CloudFront Behavior 中绑定 Lambda@Edge

- [ ] 打开 **CloudFront Console** → 选择你的 Distribution
- [ ] 选择 **Behaviors** 标签页
- [ ] 找到 `/api/products*` 的 Behavior → 点击 **Edit**
- [ ] 滚动到 **Function associations** 区域
- [ ] 在 **Origin response** 行:

| 参数 | 值 |
|------|-----|
| Function type | **Lambda@Edge** |
| Function ARN/Name | 粘贴步骤 2 中记录的版本 ARN |

- [ ] 点击 **Save changes**
- [ ] 等待 Distribution 状态变为 **Deployed**（约 3-5 分钟）

> **说明**: Lambda@Edge Origin Response 仅在 Cache Miss 时触发。如果 CloudFront 边缘节点已有缓存，直接返回缓存内容，不会触发 Lambda@Edge。这意味着只有首次请求（或缓存过期后的请求）会写入 DynamoDB。

---

## 步骤 4: 修改 Express 应用添加 Cache-Tag Header

确保 Express 应用在商品 API 响应中包含 `Cache-Tag` header。

- [ ] SSH 到 EC2 实例
- [ ] 编辑 `app/routes/products.js`

在 GET `/api/products/:id` 路由中，`res.json()` 之前添加:

```javascript
// 添加 Cache-Tag header（Lambda@Edge 会捕获并存入 DynamoDB）
const cacheTags = [
  `product-${id}`,
  product.category ? `category-${product.category}` : null,
  'product-detail',
].filter(Boolean).join(', ');

res.set('Cache-Tag', cacheTags);
```

在 GET `/api/products` 路由中，`res.json()` 之前添加:

```javascript
// 添加 Cache-Tag header
const cacheTags = ['product-list'];
if (category) cacheTags.push(`category-${category}`);
products.items.slice(0, 20).forEach(p => cacheTags.push(`product-${p.id}`));

res.set('Cache-Tag', cacheTags.join(', '));
```

- [ ] 重启 Express 应用: `pm2 restart unice`

---

## 步骤 5: 验证 Tag 注入流程

### 5.1 触发 Cache Miss 使 Lambda@Edge 执行

- [ ] 清除现有缓存（确保下次请求是 Cache Miss）:

```bash
# 失效所有商品 API 缓存
aws cloudfront create-invalidation \
  --distribution-id YOUR_DIST_ID \
  --paths "/api/products*"
```

- [ ] 等待失效完成:

```bash
aws cloudfront get-invalidation \
  --distribution-id YOUR_DIST_ID \
  --id INVALIDATION_ID
```

### 5.2 发起请求触发 tag 注入

- [ ] 请求商品详情:

```bash
# 请求商品 ID=1
curl -s -D - "https://unice.keithyu.cloud/api/products/1" | head -20
```

预期响应 headers 中 **不包含** `Cache-Tag`（已被 Lambda@Edge 删除），但包含:
```
X-Cache: Miss from cloudfront
```

- [ ] 再次请求确认缓存命中:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/1" | head -20
```

预期响应:
```
X-Cache: Hit from cloudfront
```

### 5.3 验证 DynamoDB 写入

- [ ] 打开 **DynamoDB Console** → 选择 `unice-cache-tags` 表 → **Explore table items**
- [ ] 应能看到类似记录:

| tag | url | uri | updated_at | expire_at |
|-----|-----|-----|------------|-----------|
| product-1 | /api/products/1 | /api/products/1 | 2026-04-14T10:30:00Z | 1713186600 |
| category-hair | /api/products/1 | /api/products/1 | 2026-04-14T10:30:00Z | 1713186600 |
| product-detail | /api/products/1 | /api/products/1 | 2026-04-14T10:30:00Z | 1713186600 |

- [ ] 请求商品列表触发更多 tag 注入:

```bash
curl -s "https://unice.keithyu.cloud/api/products?page=1&category=hair" > /dev/null
curl -s "https://unice.keithyu.cloud/api/products?page=1" > /dev/null
curl -s "https://unice.keithyu.cloud/api/products?category=hair&sort=price" > /dev/null
```

- [ ] 刷新 DynamoDB Console，确认新记录已写入

---

## 步骤 6: 测试标签失效

### 6.1 确认缓存存在

- [ ] 先确认缓存命中:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/1" 2>&1 | grep "X-Cache"
# 预期: X-Cache: Hit from cloudfront
```

### 6.2 调用标签失效 API

- [ ] 通过 admin API 触发失效:

```bash
curl -X POST "https://unice.keithyu.cloud/api/admin/invalidate-tag" \
  -H "Content-Type: application/json" \
  -d '{"tag": "product-1"}'
```

预期响应:

```json
{
  "message": "Tag-based invalidation completed",
  "tags": ["product-1"],
  "total_urls": 3,
  "batches": [
    {
      "invalidation_id": "I3XXXXXX",
      "paths_count": 3,
      "status": "InProgress"
    }
  ],
  "invalidated_urls": [
    "/api/products/1",
    "/api/products?page=1",
    "/api/products?page=1&category=hair"
  ],
  "mode": "direct-lambda"
}
```

### 6.3 验证缓存已失效

- [ ] 等待 1-2 秒后再次请求:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/1" 2>&1 | grep "X-Cache"
# 预期: X-Cache: Miss from cloudfront (缓存已被清除)
```

- [ ] 确认其他商品的缓存不受影响:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/2" 2>&1 | grep "X-Cache"
# 预期: X-Cache: Hit from cloudfront (product-2 的缓存未被影响)
```

### 6.4 测试按分类失效

- [ ] 失效整个 hair 分类:

```bash
curl -X POST "https://unice.keithyu.cloud/api/admin/invalidate-tag" \
  -H "Content-Type: application/json" \
  -d '{"tag": "category-hair"}'
```

- [ ] 验证 hair 分类的所有缓存路径均已失效

---

## 步骤 7: 查看管理状态

### 7.1 查看 tag 映射

- [ ] 查看特定 tag 的 URL 映射:

```bash
curl -s "https://unice.keithyu.cloud/api/admin/cache-tags?tag=product-1" | jq .
```

### 7.2 查看失效历史

- [ ] 查看 CloudFront 最近的失效记录:

```bash
curl -s "https://unice.keithyu.cloud/api/admin/invalidation-status" | jq .
```

---

## 步骤 8: 查看 Lambda@Edge 日志

Lambda@Edge 的日志存储在函数执行所在的边缘区域的 CloudWatch Logs 中。

- [ ] 打开 **CloudWatch Console**
- [ ] 切换到你测试时请求实际路由到的区域（例如从东京访问可能是 ap-northeast-1）
- [ ] **Log groups** → 搜索 `/aws/lambda/us-east-1.unice-cache-tag-origin-response`
- [ ] 查看最新的 log stream，确认 tag 解析和 DynamoDB 写入日志

> **注意**: Lambda@Edge 日志分布在各边缘区域，不一定在 us-east-1。需要在请求实际到达的区域查找日志。

---

## 常见问题

### Q1: Lambda@Edge 部署后 CloudFront Distribution 一直在 "In Progress" 状态

**原因**: Lambda@Edge 的首次关联或版本更新需要全球传播，通常需要 5-15 分钟。

**解决**: 耐心等待。可以在 CloudFront Console 查看 Distribution 状态。如果超过 30 分钟仍未完成，检查:
- Lambda 函数是否在 us-east-1
- 是否使用了已发布的版本（不是 $LATEST）
- IAM Role 的信任策略是否包含 `edgelambda.amazonaws.com`

### Q2: DynamoDB 中没有看到 tag 记录

**可能原因**:
1. **CloudFront 返回缓存命中**: 只有 Cache Miss 时才触发 Lambda@Edge Origin Response。先执行失效操作清除缓存。
2. **Express 没有返回 Cache-Tag header**: 使用 curl 直接请求源站确认:
   ```bash
   curl -s -D - "http://INTERNAL_ALB_DNS/api/products/1" | grep -i cache-tag
   ```
3. **Lambda@Edge 执行错误**: 检查 CloudWatch Logs（注意区域）。
4. **IAM 权限不足**: 确认 Lambda@Edge Role 有 DynamoDB PutItem 权限。

### Q3: Cache-Tag header 出现在浏览器 DevTools 中

**原因**: Lambda@Edge 代码中的 `delete response.headers[TAG_HEADER]` 没有正确执行。

**检查**: 确认 TAG_HEADER 变量值为小写 `cache-tag`（CloudFront 的 Origin Response 事件中 header 名均为小写）。

### Q4: 失效请求返回 "No cached URLs found"

**可能原因**:
1. DynamoDB 记录已被 TTL 自动删除（默认 24 小时后过期）
2. tag 名称不匹配（大小写敏感）: 确认请求中的 tag 与 Express 设置的 Cache-Tag 值完全一致
3. DynamoDB 查询区域不正确

### Q5: CloudFront 限制相关

| 限制 | 值 | 说明 |
|------|-----|------|
| 每次失效最大路径数 | 3000 | 超过需分批提交 |
| 同时进行的失效请求 | 3000 路径 | 排队等待 |
| 每月免费失效数 | 1000 路径 | 超过 $0.005/路径 |
| 通配符失效 | 支持 `/*` | 但 tag 方式更精确 |

### Q6: Lambda@Edge 的限制

| 限制 | Origin Response | 说明 |
|------|----------------|------|
| 执行超时 | 30 秒 | DynamoDB 写入通常 < 100ms |
| 内存 | 128 MB - 10 GB | 128 MB 足够 |
| 代码包大小 | 50 MB | 本函数 < 5KB |
| 不能访问 VPC | 是 | DynamoDB 通过公网端点访问 |
| 必须在 us-east-1 | 是 | 但会全球复制到边缘节点 |

### Q7: DynamoDB 费用估算

对于演示环境（每天约 1000 次 Cache Miss、平均每次 3 个 tag）:

| 项目 | 估算 |
|------|------|
| 写入 (PutItem) | ~3000 次/天 × $1.25/百万 = ~$0.004/天 |
| 读取 (Query) | ~100 次/天 × $0.25/百万 = ~$0.00003/天 |
| 存储 | ~100KB (极少) ≈ $0 |
| **月总计** | **< $0.15** |
```

---

### Step 21.2: 更新设计规格中的文档目录

- [ ] 修改设计规格文件 `docs/superpowers/specs/2026-04-14-cloudfront-demo-platform-design.md`

在 Section 16 (Hands-on 文档目录) 的表格末尾添加:

```markdown
| 12 | `cloudfront-tag-based-invalidation.md` | 配置 Lambda@Edge + DynamoDB 实现基于标签的精准缓存失效，替代路径通配符失效，包含 tag 注入、DynamoDB 映射、失效触发完整流程 |
```

- [ ] 更新 Section 1.3 的文档数量描述（11 篇 → 12 篇）

---

### Step 21.3: 更新项目结构和 Feature Flags

- [ ] 修改设计规格 Section 2（项目结构），添加新增文件:

```
terraform/
│   ├── modules/
│   │   ├── ...
│   │   └── tag-invalidation/       # Lambda@Edge + DynamoDB Tag-Based Invalidation
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
app/
│   ├── routes/
│   │   ├── ...
│   │   └── admin.js                # /api/admin — 管理 API（tag 失效）
hands-on/
│   ├── ...
│   └── 12-cloudfront-tag-based-invalidation.md
```

- [ ] 修改设计规格 Section 14（Feature Flags），添加:

```markdown
| `enable_tag_invalidation` | `false` | Lambda@Edge + DynamoDB 的标签缓存失效 | Lambda@Edge 按请求计费 + DynamoDB 按需 |
| `enable_tag_invalidation_step_functions` | `false` | Step Functions 编排分批失效 | $0.025/千次状态转换 |
```

---

### Step 21.4: 最终验证

- [ ] 所有文件创建完毕，检查文件路径正确:
  - `terraform/modules/tag-invalidation/main.tf`
  - `terraform/modules/tag-invalidation/variables.tf`
  - `terraform/modules/tag-invalidation/outputs.tf`
  - `app/routes/admin.js`
  - `hands-on/12-cloudfront-tag-based-invalidation.md`
- [ ] Terraform 代码: `terraform validate` 无错误
- [ ] Lambda@Edge 代码: 符合 Origin Response 事件格式
- [ ] Invalidation Lambda 代码: 支持直接调用 / HTTP / Step Functions 三种方式
- [ ] Express admin.js: `node -c app/routes/admin.js` 语法检查通过
- [ ] Hands-on 文档: 所有 Console 步骤可操作，验证命令可执行
