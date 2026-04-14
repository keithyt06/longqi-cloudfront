// =============================================================================
// 用户路由 - /api/user
// =============================================================================
// POST /api/user/register   - Cognito 注册 + DynamoDB UUID 绑定
// POST /api/user/login      - Cognito 登录 + UUID 跨设备统一 (Section 10.3)
// GET  /api/user/profile    - 用户信息 (JWT)
// GET  /api/user/signed-url - 生成 CloudFront 签名 URL (JWT)
//
// 缓存策略: CachingDisabled（涉及 Set-Cookie 操作和个人数据）
// =============================================================================

const express = require('express');
const router = express.Router();
const {
  CognitoIdentityProviderClient,
  SignUpCommand,
  InitiateAuthCommand,
  AdminConfirmSignUpCommand
} = require('@aws-sdk/client-cognito-identity-provider');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand
} = require('@aws-sdk/lib-dynamodb');
const cf = require('aws-cloudfront-sign');
const { requireAuth } = require('../middleware/cognito-auth');

// AWS SDK 客户端（延迟初始化）
const region = process.env.AWS_REGION || 'ap-northeast-1';

const cognitoClient = new CognitoIdentityProviderClient({ region });
const dynamoClient = DynamoDBDocumentClient.from(
  new DynamoDBClient({ region }),
  { marshallOptions: { removeUndefinedValues: true } }
);

// DynamoDB 表名和 Cognito 配置
const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || 'unice-trace-mapping';
const USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;
const CLIENT_ID = process.env.COGNITO_CLIENT_ID;

// CloudFront 签名 URL 配置
const CF_KEY_PAIR_ID = process.env.CF_KEY_PAIR_ID || '';
const CF_PRIVATE_KEY_PATH = process.env.CF_PRIVATE_KEY_PATH || '/opt/unice-app/cf-private-key.pem';
const CF_DOMAIN = process.env.CF_DOMAIN || 'unice.keithyu.cloud';

/**
 * POST /api/user/register
 * Cognito 注册 + DynamoDB UUID 绑定
 *
 * Body: { email, password }
 */
router.post('/register', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: '缺少必填字段: email, password',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    if (!USER_POOL_ID || !CLIENT_ID) {
      return res.status(503).json({
        error: 'Cognito 未配置',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    // 1. Cognito 注册
    const signUpResult = await cognitoClient.send(new SignUpCommand({
      ClientId: CLIENT_ID,
      Username: email,
      Password: password,
      UserAttributes: [
        { Name: 'email', Value: email }
      ]
    }));

    const cognitoUserId = signUpResult.UserSub;

    // 1.5 自动确认用户（演示平台跳过邮箱验证）
    await cognitoClient.send(new AdminConfirmSignUpCommand({
      UserPoolId: USER_POOL_ID,
      Username: email
    }));

    // 2. DynamoDB UUID 绑定（将当前 trace_id 绑定到新注册用户）
    await dynamoClient.send(new PutCommand({
      TableName: TABLE_NAME,
      Item: {
        cognito_user_id: cognitoUserId,
        trace_id: req.traceId,
        created_at: new Date().toISOString(),
        last_device: req.headers['user-agent'] || 'unknown',
        last_seen: new Date().toISOString()
      }
    }));

    console.log(`[User] 新用户注册: userId=${cognitoUserId}, traceId=${req.traceId}`);

    res.status(201).json({
      message: '注册成功，请查收验证邮件',
      userId: cognitoUserId,
      traceId: req.traceId,
      userConfirmed: signUpResult.UserConfirmed,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[User] 注册失败:', err.message);

    // Cognito 特定错误处理
    if (err.name === 'UsernameExistsException') {
      return res.status(409).json({
        error: '该邮箱已注册',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }
    if (err.name === 'InvalidPasswordException') {
      return res.status(400).json({
        error: '密码不符合要求（至少 8 位，包含大小写字母和数字）',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    res.status(500).json({
      error: '注册失败: ' + err.message,
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/user/login
 * Cognito 登录 + UUID 跨设备统一（设计规格 Section 10.3）
 *
 * 流程:
 *   1. Cognito InitiateAuth 验证用户名/密码 → 获取 JWT
 *   2. 查询 DynamoDB: unice-trace-mapping (PK=cognito_user_id)
 *   3. 记录存在 → 用数据库中的 UUID 覆盖当前 cookie（跨设备统一）
 *      记录不存在 → 将当前 req.traceId 写入 DynamoDB 绑定
 *   4. 返回 JWT + 用户信息 + trace_id
 *
 * Body: { email, password }
 */
router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body;

    if (!email || !password) {
      return res.status(400).json({
        error: '缺少必填字段: email, password',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    if (!USER_POOL_ID || !CLIENT_ID) {
      return res.status(503).json({
        error: 'Cognito 未配置',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    // 步骤 1: Cognito 验证用户名/密码 → 获取 JWT
    const authResult = await cognitoClient.send(new InitiateAuthCommand({
      AuthFlow: 'USER_PASSWORD_AUTH',
      ClientId: CLIENT_ID,
      AuthParameters: {
        USERNAME: email,
        PASSWORD: password
      }
    }));

    const tokens = authResult.AuthenticationResult;
    if (!tokens) {
      return res.status(401).json({
        error: '认证失败，可能需要完成额外验证步骤',
        challengeName: authResult.ChallengeName,
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    // 从 id_token 解析用户信息（Base64 解码 payload 部分）
    const idPayload = JSON.parse(
      Buffer.from(tokens.IdToken.split('.')[1], 'base64url').toString()
    );
    const cognitoUserId = idPayload.sub;

    // 步骤 2: 查询 DynamoDB 中的 UUID 绑定记录
    const existingRecord = await dynamoClient.send(new GetCommand({
      TableName: TABLE_NAME,
      Key: { cognito_user_id: cognitoUserId }
    }));

    let finalTraceId = req.traceId;

    if (existingRecord.Item) {
      // 步骤 3a: 记录存在 → 用数据库中的 UUID 覆盖当前 cookie（跨设备统一）
      finalTraceId = existingRecord.Item.trace_id;

      // 覆盖 cookie（统一为数据库中保存的 UUID）
      res.cookie('x-trace-id', finalTraceId, {
        path: '/',
        httpOnly: true,
        secure: true,
        sameSite: 'Lax',
        maxAge: 63072000 * 1000  // 2 年
      });

      // 更新 last_device 和 last_seen
      await dynamoClient.send(new UpdateCommand({
        TableName: TABLE_NAME,
        Key: { cognito_user_id: cognitoUserId },
        UpdateExpression: 'SET last_device = :device, last_seen = :seen',
        ExpressionAttributeValues: {
          ':device': req.headers['user-agent'] || 'unknown',
          ':seen': new Date().toISOString()
        }
      }));

      console.log(`[User] 登录(已绑定): userId=${cognitoUserId}, traceId=${finalTraceId}`);
    } else {
      // 步骤 3b: 记录不存在 → 将当前 req.traceId 写入 DynamoDB
      await dynamoClient.send(new PutCommand({
        TableName: TABLE_NAME,
        Item: {
          cognito_user_id: cognitoUserId,
          trace_id: req.traceId,
          created_at: new Date().toISOString(),
          last_device: req.headers['user-agent'] || 'unknown',
          last_seen: new Date().toISOString()
        }
      }));

      console.log(`[User] 登录(新绑定): userId=${cognitoUserId}, traceId=${req.traceId}`);
    }

    // 步骤 4: 返回 JWT + 用户信息 + trace_id
    // 更新响应头中的 X-Trace-Id（可能已被跨设备统一修改）
    res.setHeader('X-Trace-Id', finalTraceId);

    res.json({
      message: '登录成功',
      tokens: {
        accessToken: tokens.AccessToken,
        idToken: tokens.IdToken,
        refreshToken: tokens.RefreshToken,
        expiresIn: tokens.ExpiresIn
      },
      user: {
        userId: cognitoUserId,
        email: idPayload.email,
        emailVerified: idPayload.email_verified
      },
      traceId: finalTraceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[User] 登录失败:', err.message);

    if (err.name === 'NotAuthorizedException') {
      return res.status(401).json({
        error: '用户名或密码错误',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }
    if (err.name === 'UserNotConfirmedException') {
      return res.status(401).json({
        error: '账号未验证，请先完成邮箱验证',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    res.status(500).json({
      error: '登录失败: ' + err.message,
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /api/user/profile
 * 获取用户信息（需 JWT 认证）
 */
router.get('/profile', requireAuth, async (req, res) => {
  try {
    // 查询 DynamoDB 中的 UUID 绑定信息
    const record = await dynamoClient.send(new GetCommand({
      TableName: TABLE_NAME,
      Key: { cognito_user_id: req.user.sub }
    }));

    res.json({
      user: {
        userId: req.user.sub,
        username: req.user.username,
        scope: req.user.scope
      },
      traceMapping: record.Item || null,
      currentTraceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[User] 查询 profile 失败:', err.message);
    res.status(500).json({
      error: '查询个人信息失败',
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /api/user/signed-url
 * 生成 CloudFront 签名 URL（需 JWT 认证）
 *
 * 签名策略（设计规格 Section 7.2）:
 *   - 保护路径: /premium/*
 *   - 有效期: 1 小时
 *   - 不限制 IP
 */
router.get('/signed-url', requireAuth, (req, res) => {
  try {
    if (!CF_KEY_PAIR_ID) {
      return res.status(503).json({
        error: 'CloudFront 签名 URL 未配置（缺少 CF_KEY_PAIR_ID）',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    // 要签名的资源路径（默认 /premium/sample-content.html）
    const resourcePath = req.query.path || '/premium/sample-content.html';
    const url = `https://${CF_DOMAIN}${resourcePath}`;

    // 签名选项：有效期 1 小时
    const signedUrl = cf.getSignedUrl(url, {
      keypairId: CF_KEY_PAIR_ID,
      privateKeyPath: CF_PRIVATE_KEY_PATH,
      expireTime: new Date(Date.now() + 3600 * 1000) // 1 小时后过期
    });

    console.log(`[User] 签名 URL 已生成: userId=${req.user.sub}, path=${resourcePath}`);

    res.json({
      signedUrl,
      resource: resourcePath,
      expiresAt: new Date(Date.now() + 3600 * 1000).toISOString(),
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[User] 生成签名 URL 失败:', err.message);
    res.status(500).json({
      error: '生成签名 URL 失败: ' + err.message,
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
