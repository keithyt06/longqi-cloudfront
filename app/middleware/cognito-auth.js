// =============================================================================
// Cognito JWT 验证中间件
// =============================================================================
// 功能：从 Authorization: Bearer <token> 提取 JWT，使用 aws-jwt-verify 验证
//
// 验证内容：
//   - 签名有效性（自动从 Cognito JWKS 端点获取公钥）
//   - token 是否过期
//   - issuer 是否匹配 Cognito User Pool
//   - token_use 是否为 "access"
//
// 成功：req.user = { sub, email, ... }, 调用 next()
// 失败：返回 401 Unauthorized
//
// 使用方式：
//   const { requireAuth } = require('../middleware/cognito-auth');
//   router.get('/profile', requireAuth, handler);
// =============================================================================

const { CognitoJwtVerifier } = require('aws-jwt-verify');

// 延迟初始化 verifier（等待环境变量可用）
let verifier = null;

/**
 * 获取或初始化 JWT verifier
 * 延迟初始化模式：首次调用时创建，后续复用
 */
function getVerifier() {
  if (!verifier) {
    const userPoolId = process.env.COGNITO_USER_POOL_ID;
    const clientId = process.env.COGNITO_CLIENT_ID;

    if (!userPoolId || !clientId) {
      console.warn('[Auth] Cognito 未配置: COGNITO_USER_POOL_ID 或 COGNITO_CLIENT_ID 为空');
      return null;
    }

    verifier = CognitoJwtVerifier.create({
      userPoolId: userPoolId,
      tokenUse: 'access',         // 验证 access_token（不是 id_token）
      clientId: clientId
    });

    console.log(`[Auth] JWT Verifier 已初始化: userPoolId=${userPoolId}`);
  }
  return verifier;
}

/**
 * JWT 认证中间件
 * 从 Authorization header 提取 Bearer token 并验证
 */
async function requireAuth(req, res, next) {
  try {
    // 检查 Cognito 是否已配置
    const v = getVerifier();
    if (!v) {
      return res.status(503).json({
        error: 'Cognito 认证服务未配置',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    // 提取 Authorization: Bearer <token>
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        error: '未提供认证 token，请在 Authorization header 中携带 Bearer token',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    const token = authHeader.slice(7); // 去掉 "Bearer " 前缀

    // 验证 JWT（aws-jwt-verify 自动验证签名、过期时间、issuer）
    const payload = await v.verify(token);

    // 将解码后的 JWT payload 挂载到 req.user
    req.user = {
      sub: payload.sub,             // Cognito 用户唯一标识（用作 DynamoDB PK）
      username: payload.username,   // 用户名（邮箱）
      scope: payload.scope,         // 权限范围
      tokenUse: payload.token_use,
      authTime: payload.auth_time
    };

    next();
  } catch (err) {
    console.error(`[Auth] JWT 验证失败: ${err.message}`, {
      traceId: req.traceId,
      error: err.constructor.name
    });

    // 区分不同的错误类型
    if (err.message.includes('expired')) {
      return res.status(401).json({
        error: 'Token 已过期，请重新登录',
        code: 'TOKEN_EXPIRED',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    return res.status(401).json({
      error: 'Token 验证失败',
      code: 'INVALID_TOKEN',
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
}

module.exports = { requireAuth };
