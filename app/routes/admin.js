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
