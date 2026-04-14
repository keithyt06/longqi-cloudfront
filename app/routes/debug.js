// =============================================================================
// 调试路由 - /api/debug
// =============================================================================
// GET /api/debug - 返回 Express 收到的所有 HTTP headers
//
// 用途:
//   - 验证 CloudFront 是否正确转发/注入特定 header
//     例: CloudFront-Viewer-Country, X-AB-Group, X-Forwarded-For
//   - 检查 ALB 注入的 header (X-Forwarded-For, X-Forwarded-Proto)
//   - 确认 UUID cookie (x-trace-id) 是否正确传递
//   - 排查 WAF aws-waf-token cookie 是否到达源站
//
// 缓存策略: CachingDisabled（完全透传，观察每次请求的真实 headers）
// =============================================================================

const express = require('express');
const router = express.Router();

/**
 * GET /api/debug
 * 返回所有 request headers 和请求元数据
 */
router.get('/', (req, res) => {
  res.json({
    // 所有 HTTP headers（CloudFront/ALB 注入的 header 都在这里）
    headers: req.headers,

    // 请求元数据
    request: {
      method: req.method,
      url: req.url,
      originalUrl: req.originalUrl,
      path: req.path,
      protocol: req.protocol,
      hostname: req.hostname,
      ip: req.ip,
      ips: req.ips
    },

    // Cookie 解析结果
    cookies: req.cookies,

    // UUID 追踪信息
    trace: {
      traceId: req.traceId,
      isNewUser: req.isNewUser || false
    },

    // CloudFront 常见注入 headers（方便快速查看）
    cloudfront: {
      viewerCountry: req.headers['cloudfront-viewer-country'] || null,
      viewerCity: req.headers['cloudfront-viewer-city'] || null,
      isDesktop: req.headers['cloudfront-is-desktop-viewer'] || null,
      isMobile: req.headers['cloudfront-is-mobile-viewer'] || null,
      isTablet: req.headers['cloudfront-is-tablet-viewer'] || null,
      forwardedFor: req.headers['x-forwarded-for'] || null,
      forwardedProto: req.headers['x-forwarded-proto'] || null
    },

    // A/B 测试分组（由 CloudFront Function 注入）
    abTest: {
      group: req.headers['x-ab-group'] || req.cookies['x-ab-group'] || null
    },

    timestamp: new Date().toISOString()
  });
});

module.exports = router;
