// =============================================================================
// 健康检查路由 - /api/health
// =============================================================================
// GET /api/health - 返回服务状态
//
// 用途:
//   1. ALB Target Group 健康检查（每 30 秒探测一次）
//   2. CloudFront Origin 可达性检查
//   3. 运维监控和告警
//
// 缓存策略: CachingDisabled
// =============================================================================

const express = require('express');
const router = express.Router();

/**
 * GET /api/health
 * 返回服务运行状态、环境配置信息和当前 trace ID
 */
router.get('/', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    traceId: req.traceId,
    version: '1.0.0',
    uptime: Math.floor(process.uptime()),
    env: {
      nodeEnv: process.env.NODE_ENV || 'development',
      region: process.env.AWS_REGION || 'unknown',
      dbConfigured: !!process.env.DB_HOST,
      cognitoConfigured: !!process.env.COGNITO_USER_POOL_ID,
      dynamoConfigured: !!process.env.DYNAMODB_TABLE_NAME
    }
  });
});

module.exports = router;
