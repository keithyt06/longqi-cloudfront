// =============================================================================
// UUID 追踪中间件
// =============================================================================
// 功能：为每个请求分配唯一的 UUID (x-trace-id)，存储在 HttpOnly cookie 中
//
// 流程（参考设计规格 Section 10.2）：
//   1. 读取 cookie: x-trace-id
//   2. 有 cookie → req.traceId = cookie 值，继续处理
//   3. 无 cookie → 生成 UUID v4
//      - Set-Cookie: x-trace-id=<UUID>; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=63072000
//      - req.traceId = 新 UUID, req.isNewUser = true
//   4. 所有响应 header 添加 X-Trace-Id: <UUID>
//
// Cookie 有效期：2 年 (63072000 秒)
// 安全特性：HttpOnly (前端 JS 无法读取), Secure (仅 HTTPS), SameSite=Lax
// =============================================================================

const { v4: uuidv4 } = require('uuid');

// Cookie 名称（与 CloudFront Behavior 转发列表一致）
const COOKIE_NAME = 'x-trace-id';

// Cookie 有效期：2 年（秒）
const MAX_AGE = 63072000;

/**
 * UUID 追踪中间件
 * 为每个请求分配/恢复 UUID，通过 HttpOnly cookie 持久化
 */
function uuidTracker(req, res, next) {
  // 尝试从 cookie 读取已有的 trace ID
  let traceId = req.cookies[COOKIE_NAME];
  let isNewUser = false;

  if (!traceId) {
    // 新用户：生成 UUID v4
    traceId = uuidv4();
    isNewUser = true;

    // 设置 cookie（HttpOnly 防止 XSS 窃取，Secure 仅 HTTPS 传输）
    res.cookie(COOKIE_NAME, traceId, {
      path: '/',
      httpOnly: true,
      secure: true,
      sameSite: 'Lax',
      maxAge: MAX_AGE * 1000  // express cookie maxAge 单位是毫秒
    });
  }

  // 挂载到 req 对象，所有下游路由可直接使用
  req.traceId = traceId;
  req.isNewUser = isNewUser;

  // 响应头添加 X-Trace-Id（方便通过浏览器 DevTools 或 curl 查看）
  res.setHeader('X-Trace-Id', traceId);

  next();
}

module.exports = uuidTracker;
