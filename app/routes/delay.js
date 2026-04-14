// =============================================================================
// 延迟模拟路由 - /api/delay/:ms
// =============================================================================
// GET /api/delay/:ms - 等待指定毫秒后响应
//
// 用途:
//   - 测试 CloudFront Origin Response Timeout（默认 30 秒）
//   - 观察 CloudFront 在源站慢响应时的行为
//   - 模拟 Origin Shield 缓存对慢源站的保护效果
//   - 验证 ALB idle timeout 配置（默认 60 秒）
//
// 安全限制: 最大延迟 30000ms (30 秒)，防止资源耗尽
// 缓存策略: CachingDisabled
// =============================================================================

const express = require('express');
const router = express.Router();

// 最大允许延迟（毫秒），防止恶意请求占用服务器资源
const MAX_DELAY_MS = 30000;

/**
 * GET /api/delay/:ms
 * 等待指定毫秒数后返回响应
 *
 * 参数:
 *   :ms - 延迟毫秒数（1 ~ 30000）
 */
router.get('/:ms', (req, res) => {
  const requestedMs = parseInt(req.params.ms, 10) || 1000;
  const delayMs = Math.min(Math.max(1, requestedMs), MAX_DELAY_MS);

  const startTime = Date.now();

  setTimeout(() => {
    const actualDelay = Date.now() - startTime;

    res.json({
      requested: requestedMs,
      capped: delayMs,
      actual: actualDelay,
      maxAllowed: MAX_DELAY_MS,
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }, delayMs);
});

module.exports = router;
