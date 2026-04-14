# CloudFront 全功能演示平台 - 实施计划 Part 2A

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 Express 应用核心——脚手架、中间件、路由和数据库初始化脚本，使 EC2 上的 Node.js 服务具备完整的 API 功能，为 Part 2B（前端 EJS 模板）和 Part 3（CloudFront/WAF/Functions Terraform 模块）提供后端基础。

**Architecture:** Express 4.x 应用，监听 port 3000，通过 Internal ALB 接收来自 CloudFront VPC Origin 的流量。Cognito JWT 认证、DynamoDB UUID 绑定、Aurora PG 商品/订单查询、CloudFront 签名 URL 生成。

**Tech Stack:** Node.js 20, Express 4, EJS, pg, aws-jwt-verify, @aws-sdk (Cognito/DynamoDB), aws-cloudfront-sign, cookie-parser, uuid

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/app/`

**Depends On:** Part 1 (Terraform 基础设施已 apply，EC2 user_data.sh 已安装 Node.js 20 + pm2)

---

## 文件结构总览 (Part 2A)

```
app/
├── package.json                   # 依赖清单
├── server.js                      # Express 主入口 (port 3000)
├── db.js                          # PostgreSQL 连接池 (pg.Pool)
├── middleware/
│   ├── uuid-tracker.js            # UUID cookie 中间件 (x-trace-id)
│   └── cognito-auth.js            # Cognito JWT 验证中间件
├── routes/
│   ├── products.js                # /api/products - 商品列表/详情
│   ├── user.js                    # /api/user - 注册/登录/个人信息/签名URL
│   ├── cart.js                    # /api/cart - 购物车 CRUD (内存 Map)
│   ├── orders.js                  # /api/orders - 订单列表/创建
│   ├── health.js                  # /api/health - 健康检查
│   ├── debug.js                   # /api/debug - 调试 headers
│   └── delay.js                   # /api/delay/:ms - 延迟模拟
└── seed.js                        # 数据库初始化 + 25 条模拟商品
```

---

## Task 7: Express 脚手架 + 中间件

创建 Express 应用基础骨架：`package.json` 声明所有依赖，`server.js` 作为主入口加载中间件和路由，`db.js` 封装 PostgreSQL 连接池，`uuid-tracker.js` 实现 UUID cookie 追踪，`cognito-auth.js` 实现 JWT 验证守卫。

### Step 7.1: 创建 `app/package.json`

- [ ] 创建文件 `app/package.json`，声明所有运行时依赖

```json
{
  "name": "unice-demo",
  "version": "1.0.0",
  "description": "CloudFront 全功能演示平台 - Unice 电商模拟",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "node --watch server.js",
    "seed": "node seed.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "ejs": "^3.1.10",
    "express-ejs-layouts": "^2.5.1",
    "cookie-parser": "^1.4.7",
    "uuid": "^11.1.0",
    "aws-jwt-verify": "^4.0.1",
    "@aws-sdk/client-cognito-identity-provider": "^3.700.0",
    "@aws-sdk/client-dynamodb": "^3.700.0",
    "@aws-sdk/lib-dynamodb": "^3.700.0",
    "pg": "^8.13.0",
    "aws-cloudfront-sign": "^3.0.2",
    "dotenv": "^16.4.0"
  },
  "engines": {
    "node": ">=20.0.0"
  }
}
```

### Step 7.2: 创建 `app/server.js`

- [ ] 创建文件 `app/server.js`，Express 主入口，加载中间件、挂载路由、设置 view engine

```js
// =============================================================================
// Unice Demo - Express 主入口
// =============================================================================
// 架构: CloudFront → VPC Origin → Internal ALB (port 80) → Express (port 3000)
// 功能: 电商模拟 API + EJS 页面渲染 + UUID 追踪 + Cognito JWT 认证
// =============================================================================

require('dotenv').config();
const express = require('express');
const path = require('path');
const cookieParser = require('cookie-parser');
const uuidTracker = require('./middleware/uuid-tracker');
const expressLayouts = require('express-ejs-layouts');

const app = express();
const PORT = process.env.PORT || 3000;

// =============================================================================
// 视图引擎配置
// =============================================================================
app.set('view engine', 'ejs');
app.set('views', path.join(__dirname, 'views'));
app.set('layout', 'layout');
app.use(expressLayouts);

// =============================================================================
// 全局中间件
// =============================================================================

// 解析 JSON 请求体（POST /api/cart, /api/orders 等）
app.use(express.json());

// 解析 URL 编码的表单数据（POST /api/user/login 表单提交）
app.use(express.urlencoded({ extended: true }));

// Cookie 解析（读取 x-trace-id、aws-waf-token 等 cookie）
app.use(cookieParser());

// UUID 追踪中间件（为每个请求分配/恢复 x-trace-id cookie）
// 必须在路由之前加载，确保 req.traceId 在所有路由中可用
app.use(uuidTracker);

// 静态文件服务（本地开发用，生产环境由 CloudFront → S3 分发）
app.use('/public', express.static(path.join(__dirname, 'public')));

// =============================================================================
// 路由挂载
// =============================================================================

// 调试/工具路由（无需认证）
const healthRouter = require('./routes/health');
const debugRouter = require('./routes/debug');
const delayRouter = require('./routes/delay');

app.use('/api/health', healthRouter);
app.use('/api/debug', debugRouter);
app.use('/api/delay', delayRouter);

// 业务路由
const productsRouter = require('./routes/products');
const userRouter = require('./routes/user');
const cartRouter = require('./routes/cart');
const ordersRouter = require('./routes/orders');

app.use('/api/products', productsRouter);
app.use('/api/user', userRouter);
app.use('/api/cart', cartRouter);
app.use('/api/orders', ordersRouter);

// =============================================================================
// 默认路由（首页占位，Part 2B 替换为 EJS 模板渲染）
// =============================================================================
app.get('/', (req, res) => {
  res.send([
    '<h1>Unice Demo - CloudFront 全功能演示平台</h1>',
    '<p>Platform is running. Trace ID: ' + req.traceId + '</p>',
    '<ul>',
    '<li><a href="/api/health">/api/health</a> - 健康检查</li>',
    '<li><a href="/api/debug">/api/debug</a> - 调试 Headers</li>',
    '<li><a href="/api/products">/api/products</a> - 商品列表</li>',
    '<li><a href="/api/delay/1000">/api/delay/1000</a> - 1秒延迟测试</li>',
    '</ul>'
  ].join('\n'));
});

// =============================================================================
// 404 处理
// =============================================================================
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found',
    path: req.originalUrl,
    traceId: req.traceId,
    timestamp: new Date().toISOString()
  });
});

// =============================================================================
// 全局错误处理
// =============================================================================
app.use((err, req, res, _next) => {
  console.error(`[ERROR] ${req.method} ${req.originalUrl} - traceId: ${req.traceId}`, err);
  res.status(err.status || 500).json({
    error: err.message || 'Internal Server Error',
    traceId: req.traceId,
    timestamp: new Date().toISOString()
  });
});

// =============================================================================
// 启动服务器
// =============================================================================
app.listen(PORT, '0.0.0.0', () => {
  console.log(`[Unice Demo] 服务器启动 port=${PORT} env=${process.env.NODE_ENV || 'development'}`);
  console.log(`[Unice Demo] DB_HOST=${process.env.DB_HOST ? '已配置' : '未配置'}`);
  console.log(`[Unice Demo] COGNITO=${process.env.COGNITO_USER_POOL_ID ? '已配置' : '未配置'}`);
});

module.exports = app;
```

### Step 7.3: 创建 `app/db.js`

- [ ] 创建文件 `app/db.js`，封装 PostgreSQL 连接池，从环境变量读取连接信息

```js
// =============================================================================
// PostgreSQL 数据库连接池
// =============================================================================
// 使用 pg.Pool 管理连接，自动处理连接复用和超时回收
// 所有环境变量由 Terraform user_data.sh 写入 /opt/unice-app/.env
// =============================================================================

const { Pool } = require('pg');

// 连接池配置
const pool = new Pool({
  host: process.env.DB_HOST,         // Aurora 集群写入端点
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  database: process.env.DB_NAME || 'unice',
  user: process.env.DB_USER || 'unice_admin',
  password: process.env.DB_PASSWORD,

  // 连接池参数
  max: 10,                           // 最大连接数（演示环境足够）
  idleTimeoutMillis: 30000,          // 空闲连接 30 秒后释放
  connectionTimeoutMillis: 5000,     // 连接超时 5 秒

  // SSL 配置（Aurora 默认启用 SSL）
  ssl: process.env.DB_SSL === 'false' ? false : { rejectUnauthorized: false }
});

// 连接错误处理
pool.on('error', (err) => {
  console.error('[DB] 连接池异常断开:', err.message);
});

// 连接就绪日志
pool.on('connect', () => {
  console.log('[DB] 新连接已建立');
});

/**
 * 执行 SQL 查询
 * @param {string} text - SQL 语句
 * @param {Array} params - 参数化查询的参数
 * @returns {Promise<import('pg').QueryResult>}
 */
const query = (text, params) => pool.query(text, params);

module.exports = { pool, query };
```

### Step 7.4: 创建 `app/middleware/uuid-tracker.js`

- [ ] 创建文件 `app/middleware/uuid-tracker.js`，实现设计规格 Section 10.2 的 UUID 追踪中间件

```js
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
```

### Step 7.5: 创建 `app/middleware/cognito-auth.js`

- [ ] 创建文件 `app/middleware/cognito-auth.js`，使用 aws-jwt-verify 验证 Cognito JWT

```js
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
```

---

## Task 8: 核心路由

创建 4 个业务路由模块：`products.js`（商品查询，可缓存）、`user.js`（Cognito 注册/登录 + UUID 跨设备绑定 + 签名 URL 生成）、`cart.js`（内存购物车）、`orders.js`（订单 CRUD）。

### Step 8.1: 创建 `app/routes/products.js`

- [ ] 创建文件 `app/routes/products.js`，实现商品列表和详情查询（Aurora PG）

```js
// =============================================================================
// 商品路由 - /api/products
// =============================================================================
// GET /api/products         - 商品列表（支持分页、分类筛选、排序）
// GET /api/products/:id     - 商品详情
//
// 缓存策略（CloudFront Behavior）:
//   Path: /api/products*
//   Cache Policy: 自定义 ProductCache (3600s)
//   Cache Key: Query String 全部转发（page/category/sort 作为缓存键）
//   Header 转发: Accept, Accept-Language
// =============================================================================

const express = require('express');
const router = express.Router();
const { query } = require('../db');

/**
 * GET /api/products
 * 商品列表，支持分页/分类/排序
 *
 * Query 参数:
 *   page     - 页码，默认 1
 *   limit    - 每页条数，默认 12，最大 50
 *   category - 分类筛选（精确匹配）
 *   sort     - 排序方式: price_asc / price_desc / newest / name
 */
router.get('/', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 12));
    const offset = (page - 1) * limit;
    const category = req.query.category || null;
    const sort = req.query.sort || 'newest';

    // 构建排序子句（白名单防 SQL 注入）
    const sortMap = {
      price_asc: 'price ASC',
      price_desc: 'price DESC',
      newest: 'created_at DESC',
      name: 'name ASC'
    };
    const orderBy = sortMap[sort] || sortMap.newest;

    // 构建查询（参数化查询防 SQL 注入）
    let sql = 'SELECT * FROM products';
    let countSql = 'SELECT COUNT(*) FROM products';
    const params = [];
    const countParams = [];

    if (category) {
      sql += ' WHERE category = $1';
      countSql += ' WHERE category = $1';
      params.push(category);
      countParams.push(category);
    }

    sql += ` ORDER BY ${orderBy} LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    // 并行查询：商品列表 + 总数
    const [productsResult, countResult] = await Promise.all([
      query(sql, params),
      query(countSql, countParams)
    ]);

    const total = parseInt(countResult.rows[0].count, 10);
    const totalPages = Math.ceil(total / limit);

    res.json({
      products: productsResult.rows,
      pagination: {
        page,
        limit,
        total,
        totalPages,
        hasNext: page < totalPages,
        hasPrev: page > 1
      },
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[Products] 查询商品列表失败:', err.message);

    // 数据库未就绪时返回模拟数据（方便开发调试）
    if (err.message.includes('ECONNREFUSED') || err.message.includes('does not exist')) {
      return res.json({
        products: [],
        pagination: { page: 1, limit: 12, total: 0, totalPages: 0, hasNext: false, hasPrev: false },
        warning: '数据库未就绪，请运行 npm run seed 初始化',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    res.status(500).json({
      error: '查询商品失败',
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * GET /api/products/:id
 * 商品详情
 */
router.get('/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id) || id < 1) {
      return res.status(400).json({
        error: '无效的商品 ID',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    const result = await query('SELECT * FROM products WHERE id = $1', [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        error: '商品不存在',
        productId: id,
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    res.json({
      product: result.rows[0],
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[Products] 查询商品详情失败:', err.message);
    res.status(500).json({
      error: '查询商品失败',
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
```

### Step 8.2: 创建 `app/routes/user.js`

- [ ] 创建文件 `app/routes/user.js`，实现 Cognito 注册/登录 + UUID 跨设备绑定 + 签名 URL 生成（设计规格 Section 10.3）

```js
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
  InitiateAuthCommand
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
      return res.status(403).json({
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
```

### Step 8.3: 创建 `app/routes/cart.js`

- [ ] 创建文件 `app/routes/cart.js`，实现内存购物车（以 traceId 为 key 的 Map）

```js
// =============================================================================
// 购物车路由 - /api/cart
// =============================================================================
// GET    /api/cart         - 获取购物车内容
// POST   /api/cart         - 添加商品到购物车
// DELETE /api/cart         - 清空购物车 / 删除指定商品
//
// 存储方式: 内存 Map，以 x-trace-id (UUID) 为 key
//   - 演示目的，重启后数据丢失
//   - 生产环境应使用 DynamoDB 或 ElastiCache Redis
//
// 缓存策略: CachingDisabled（购物车强依赖用户身份，必须禁用缓存）
// =============================================================================

const express = require('express');
const router = express.Router();

// 内存购物车存储: Map<traceId, CartItem[]>
// CartItem = { productId, name, price, quantity, addedAt }
const carts = new Map();

/**
 * GET /api/cart
 * 获取当前用户的购物车内容
 */
router.get('/', (req, res) => {
  const traceId = req.traceId;
  const items = carts.get(traceId) || [];

  // 计算合计金额
  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);

  res.json({
    items,
    itemCount: items.length,
    totalQuantity: items.reduce((sum, item) => sum + item.quantity, 0),
    total: Math.round(total * 100) / 100, // 保留 2 位小数
    traceId,
    timestamp: new Date().toISOString()
  });
});

/**
 * POST /api/cart
 * 添加商品到购物车
 *
 * Body: { productId, name, price, quantity? }
 *   - quantity 默认为 1
 *   - 如果已存在相同 productId，则累加数量
 */
router.post('/', (req, res) => {
  const traceId = req.traceId;
  const { productId, name, price, quantity } = req.body;

  // 参数校验
  if (!productId || !name || price === undefined) {
    return res.status(400).json({
      error: '缺少必填字段: productId, name, price',
      traceId,
      timestamp: new Date().toISOString()
    });
  }

  const numPrice = parseFloat(price);
  const numQuantity = Math.max(1, parseInt(quantity, 10) || 1);

  if (isNaN(numPrice) || numPrice < 0) {
    return res.status(400).json({
      error: '无效的价格',
      traceId,
      timestamp: new Date().toISOString()
    });
  }

  // 获取或创建购物车
  if (!carts.has(traceId)) {
    carts.set(traceId, []);
  }
  const cart = carts.get(traceId);

  // 检查是否已存在相同商品
  const existingIndex = cart.findIndex(item => item.productId === productId);

  if (existingIndex >= 0) {
    // 已存在：累加数量
    cart[existingIndex].quantity += numQuantity;
    cart[existingIndex].updatedAt = new Date().toISOString();
  } else {
    // 不存在：添加新商品
    cart.push({
      productId,
      name,
      price: numPrice,
      quantity: numQuantity,
      addedAt: new Date().toISOString()
    });
  }

  const total = cart.reduce((sum, item) => sum + item.price * item.quantity, 0);

  res.status(201).json({
    message: '商品已添加到购物车',
    items: cart,
    itemCount: cart.length,
    total: Math.round(total * 100) / 100,
    traceId,
    timestamp: new Date().toISOString()
  });
});

/**
 * DELETE /api/cart
 * 清空购物车或删除指定商品
 *
 * Query: ?productId=xxx  → 删除指定商品
 * 无参数               → 清空整个购物车
 */
router.delete('/', (req, res) => {
  const traceId = req.traceId;
  const { productId } = req.query;

  if (productId) {
    // 删除指定商品
    const cart = carts.get(traceId) || [];
    const newCart = cart.filter(item => item.productId !== productId);

    if (newCart.length === cart.length) {
      return res.status(404).json({
        error: '购物车中没有该商品',
        productId,
        traceId,
        timestamp: new Date().toISOString()
      });
    }

    carts.set(traceId, newCart);

    const total = newCart.reduce((sum, item) => sum + item.price * item.quantity, 0);
    res.json({
      message: '商品已从购物车移除',
      removedProductId: productId,
      items: newCart,
      itemCount: newCart.length,
      total: Math.round(total * 100) / 100,
      traceId,
      timestamp: new Date().toISOString()
    });
  } else {
    // 清空整个购物车
    carts.delete(traceId);
    res.json({
      message: '购物车已清空',
      items: [],
      itemCount: 0,
      total: 0,
      traceId,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
```

### Step 8.4: 创建 `app/routes/orders.js`

- [ ] 创建文件 `app/routes/orders.js`，实现订单列表和创建（JWT + Aurora PG）

```js
// =============================================================================
// 订单路由 - /api/orders
// =============================================================================
// GET  /api/orders   - 获取当前用户的订单列表 (JWT)
// POST /api/orders   - 创建新订单 (JWT)
//
// 缓存策略: CachingDisabled（订单数据高度个性化）
// =============================================================================

const express = require('express');
const router = express.Router();
const { query } = require('../db');
const { requireAuth } = require('../middleware/cognito-auth');

/**
 * GET /api/orders
 * 获取当前用户的订单列表（需 JWT 认证）
 *
 * Query: ?page=1&limit=10
 */
router.get('/', requireAuth, async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = Math.min(50, Math.max(1, parseInt(req.query.limit, 10) || 10));
    const offset = (page - 1) * limit;

    const cognitoUserId = req.user.sub;

    // 并行查询：订单列表 + 总数
    const [ordersResult, countResult] = await Promise.all([
      query(
        `SELECT id, trace_id, items_json, total, status, created_at
         FROM orders
         WHERE cognito_user_id = $1
         ORDER BY created_at DESC
         LIMIT $2 OFFSET $3`,
        [cognitoUserId, limit, offset]
      ),
      query(
        'SELECT COUNT(*) FROM orders WHERE cognito_user_id = $1',
        [cognitoUserId]
      )
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    res.json({
      orders: ordersResult.rows,
      pagination: {
        page,
        limit,
        total,
        totalPages: Math.ceil(total / limit)
      },
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[Orders] 查询订单失败:', err.message);

    // 数据库未就绪时返回空列表
    if (err.message.includes('ECONNREFUSED') || err.message.includes('does not exist')) {
      return res.json({
        orders: [],
        pagination: { page: 1, limit: 10, total: 0, totalPages: 0 },
        warning: '数据库未就绪，请运行 npm run seed 初始化',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    res.status(500).json({
      error: '查询订单失败',
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

/**
 * POST /api/orders
 * 创建新订单（需 JWT 认证）
 *
 * Body: { items: [{ productId, name, price, quantity }] }
 */
router.post('/', requireAuth, async (req, res) => {
  try {
    const { items } = req.body;

    if (!items || !Array.isArray(items) || items.length === 0) {
      return res.status(400).json({
        error: '订单必须包含至少一个商品',
        traceId: req.traceId,
        timestamp: new Date().toISOString()
      });
    }

    // 校验每个商品项
    for (const item of items) {
      if (!item.productId || !item.name || item.price === undefined || !item.quantity) {
        return res.status(400).json({
          error: '每个商品项必须包含 productId, name, price, quantity',
          traceId: req.traceId,
          timestamp: new Date().toISOString()
        });
      }
    }

    // 计算总金额
    const total = items.reduce((sum, item) => {
      return sum + parseFloat(item.price) * parseInt(item.quantity, 10);
    }, 0);

    const cognitoUserId = req.user.sub;

    // 插入订单记录
    const result = await query(
      `INSERT INTO orders (cognito_user_id, trace_id, items_json, total, status)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING id, cognito_user_id, trace_id, items_json, total, status, created_at`,
      [
        cognitoUserId,
        req.traceId,
        JSON.stringify(items),
        Math.round(total * 100) / 100,
        'pending'
      ]
    );

    console.log(`[Orders] 新订单: orderId=${result.rows[0].id}, userId=${cognitoUserId}, total=${total}`);

    res.status(201).json({
      message: '订单创建成功',
      order: result.rows[0],
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('[Orders] 创建订单失败:', err.message);
    res.status(500).json({
      error: '创建订单失败',
      traceId: req.traceId,
      timestamp: new Date().toISOString()
    });
  }
});

module.exports = router;
```

---

## Task 9: 调试路由 + seed 脚本

创建 3 个调试/工具路由（health、debug、delay）和数据库初始化脚本（创建 products/orders 表 + 插入 25 条假发/美发风格模拟商品）。

### Step 9.1: 创建 `app/routes/health.js`

- [ ] 创建文件 `app/routes/health.js`，实现 ALB 健康检查端点

```js
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
```

### Step 9.2: 创建 `app/routes/debug.js`

- [ ] 创建文件 `app/routes/debug.js`，实现调试端点（返回所有 request headers）

```js
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
```

### Step 9.3: 创建 `app/routes/delay.js`

- [ ] 创建文件 `app/routes/delay.js`，实现延迟模拟端点

```js
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
```

### Step 9.4: 创建 `app/seed.js`

- [ ] 创建文件 `app/seed.js`，创建 products/orders 表 + 插入 25 条模拟商品（假发/美发产品风格）

```js
// =============================================================================
// 数据库初始化脚本 (seed)
// =============================================================================
// 用法: node seed.js  或  npm run seed
//
// 功能:
//   1. 创建 products 表（如果不存在）
//   2. 创建 orders 表（如果不存在）
//   3. 插入 25 条模拟商品数据（假发/美发产品风格，参考 unice.com）
//
// 环境变量: DB_HOST, DB_NAME, DB_USER, DB_PASSWORD (来自 .env)
// =============================================================================

require('dotenv').config();
const { pool } = require('./db');

// 25 条模拟商品数据（假发/美发产品风格）
const PRODUCTS = [
  // === 假发类 (Wigs) ===
  { name: 'Body Wave 蕾丝前发假发 13x4', category: '假发', price: 189.99, image_url: '/images/products/body-wave-wig.jpg', description: '巴西真人发，Body Wave 纹理，13x4 蕾丝前发，自然发际线，可自由分缝。适合日常佩戴和特殊场合。' },
  { name: 'Straight 直发蕾丝假发 4x4', category: '假发', price: 159.99, image_url: '/images/products/straight-wig.jpg', description: '印度真人发，顺滑直发，4x4 蕾丝闭合，轻薄透气，佩戴舒适。长度 18-30 英寸可选。' },
  { name: 'Deep Wave 深波浪全蕾丝假发', category: '假发', price: 259.99, image_url: '/images/products/deep-wave-wig.jpg', description: '高端全蕾丝假发，Deep Wave 纹理，360 度自然效果，预拔发际线，可高马尾。' },
  { name: 'Water Wave 水波纹假发 HD 蕾丝', category: '假发', price: 219.99, image_url: '/images/products/water-wave-wig.jpg', description: 'HD 高清蕾丝，水波纹卷发，蕾丝隐形自然，无胶佩戴设计。密度 180%。' },
  { name: 'Kinky Curly 非洲卷假发 V-Part', category: '假发', price: 139.99, image_url: '/images/products/kinky-curly-wig.jpg', description: 'V 型分缝设计，无需胶水，Kinky Curly 自然卷曲纹理，适合非裔发质融合。' },
  { name: 'Highlight 挑染假发 蜂蜜金棕', category: '假发', price: 199.99, image_url: '/images/products/highlight-wig.jpg', description: '蜂蜜金 + 棕色挑染，Piano Color #4/27，时尚渐变效果，13x4 蕾丝前发。' },
  { name: 'Bob 短发假发 10 英寸', category: '假发', price: 99.99, image_url: '/images/products/bob-wig.jpg', description: '经典 Bob 短发造型，10 英寸，轻便透气，日常通勤首选。多色可选。' },
  { name: 'Glueless 免胶假发 Wear & Go', category: '假发', price: 179.99, image_url: '/images/products/glueless-wig.jpg', description: '革新免胶设计，3 秒佩戴，预剪蕾丝，弹性松紧带 + 梳子固定。新手友好。' },

  // === 接发/发束类 (Hair Bundles) ===
  { name: 'Body Wave 发束 3 件装', category: '发束', price: 129.99, image_url: '/images/products/body-wave-bundles.jpg', description: '巴西真人发束 3 件套，Body Wave 纹理，可染色可烫。重量 100g/束。' },
  { name: 'Straight 直发束 4 件 + 闭合片', category: '发束', price: 169.99, image_url: '/images/products/straight-bundles.jpg', description: '4 束直发 + 4x4 闭合片套装，顺滑柔软，最小脱落，持久耐用。' },
  { name: 'Curly 卷发束 Frontal 套装', category: '发束', price: 189.99, image_url: '/images/products/curly-bundles.jpg', description: '3 束深卷发 + 13x4 蕾丝正面片套装，弹性卷度，自然蓬松效果。' },
  { name: 'Loose Wave 松散波浪发束', category: '发束', price: 109.99, image_url: '/images/products/loose-wave-bundles.jpg', description: '秘鲁真人发，松散波浪纹理，柔软有光泽。单束 100g，长度 10-30 英寸。' },

  // === 蕾丝闭合片 (Closures & Frontals) ===
  { name: '4x4 蕾丝闭合片 Straight', category: '蕾丝片', price: 59.99, image_url: '/images/products/4x4-closure.jpg', description: '4x4 瑞士蕾丝闭合片，直发纹理，自由分缝/中分/三分可选。预拔婴儿发。' },
  { name: '13x4 蕾丝正面片 Body Wave', category: '蕾丝片', price: 89.99, image_url: '/images/products/13x4-frontal.jpg', description: '13x4 耳到耳蕾丝正面片，Body Wave 纹理，HD 高清蕾丝，隐形自然。' },
  { name: '5x5 HD 蕾丝闭合片 Deep Wave', category: '蕾丝片', price: 79.99, image_url: '/images/products/5x5-closure.jpg', description: '5x5 大面积闭合，HD 蕾丝超薄隐形，Deep Wave 纹理。更大分缝自由度。' },

  // === 护发产品 (Hair Care) ===
  { name: '摩洛哥坚果油精华素 100ml', category: '护发', price: 24.99, image_url: '/images/products/argan-oil.jpg', description: '100% 纯天然摩洛哥坚果油，修复受损发质，增加光泽，减少毛躁。适合真人发假发保养。' },
  { name: '假发专用洗发水 & 护发素套装', category: '护发', price: 29.99, image_url: '/images/products/wig-shampoo-set.jpg', description: '温和无硫酸盐配方，专为真人发假发设计。保持纹理弹性，延长使用寿命。' },
  { name: '防热喷雾 200ml', category: '护发', price: 18.99, image_url: '/images/products/heat-protectant.jpg', description: '最高 450°F 热保护，卷发棒/直板夹使用前必备。不残留不油腻。' },
  { name: '深层修复发膜 250ml', category: '护发', price: 34.99, image_url: '/images/products/hair-mask.jpg', description: '角蛋白深层修复发膜，15 分钟密集修护，恢复发丝弹性和光泽。每周使用 1-2 次。' },

  // === 工具配件 (Tools & Accessories) ===
  { name: '假发头模 泡沫头架', category: '配件', price: 12.99, image_url: '/images/products/wig-head.jpg', description: '轻质泡沫头模，适合假发存放、造型和展示。22 英寸标准尺寸。' },
  { name: '蕾丝假发胶水 强力防水', category: '配件', price: 15.99, image_url: '/images/products/wig-glue.jpg', description: '防水蕾丝胶水，持久固定 4-6 周，温和不伤皮肤，轻松卸除。' },
  { name: '假发弹力网帽 2 件装', category: '配件', price: 8.99, image_url: '/images/products/wig-cap.jpg', description: '透气弹力网帽，佩戴假发前使用，固定自然发，减少滑动。均码适合大多数头型。' },
  { name: '宽齿梳 防静电木梳', category: '配件', price: 9.99, image_url: '/images/products/wide-tooth-comb.jpg', description: '天然檀木宽齿梳，防静电，温和梳理湿发和假发，减少拉扯和断裂。' },
  { name: '缎面枕套 真丝护发枕套', category: '配件', price: 19.99, image_url: '/images/products/satin-pillowcase.jpg', description: '100% 桑蚕丝枕套，减少睡眠时发丝摩擦，保护假发纹理，延长使用寿命。' },
  { name: '发际线假发贴 隐形双面胶', category: '配件', price: 11.99, image_url: '/images/products/wig-tape.jpg', description: '超薄隐形双面胶带，发际线固定专用，防水透气，易撕不残留。36 片/包。' }
];

/**
 * 主函数：创建表 + 插入种子数据
 */
async function seed() {
  const client = await pool.connect();

  try {
    console.log('[Seed] 开始数据库初始化...');
    console.log(`[Seed] 连接: ${process.env.DB_HOST}/${process.env.DB_NAME}`);

    await client.query('BEGIN');

    // ─── 创建 products 表 ─────────────────────────────────────────
    console.log('[Seed] 创建 products 表...');
    await client.query(`
      CREATE TABLE IF NOT EXISTS products (
        id SERIAL PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        category VARCHAR(100),
        price DECIMAL(10,2),
        image_url VARCHAR(500),
        description TEXT,
        created_at TIMESTAMP DEFAULT NOW()
      )
    `);

    // ─── 创建 orders 表 ──────────────────────────────────────────
    console.log('[Seed] 创建 orders 表...');
    await client.query(`
      CREATE TABLE IF NOT EXISTS orders (
        id SERIAL PRIMARY KEY,
        cognito_user_id VARCHAR(255) NOT NULL,
        trace_id VARCHAR(36),
        items_json JSONB,
        total DECIMAL(10,2),
        status VARCHAR(50) DEFAULT 'pending',
        created_at TIMESTAMP DEFAULT NOW()
      )
    `);

    // ─── 创建索引 ────────────────────────────────────────────────
    console.log('[Seed] 创建索引...');

    // products 表索引
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_products_price ON products(price)
    `);

    // orders 表索引
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_orders_cognito_user_id ON orders(cognito_user_id)
    `);
    await client.query(`
      CREATE INDEX IF NOT EXISTS idx_orders_trace_id ON orders(trace_id)
    `);

    // ─── 检查是否已有数据 ────────────────────────────────────────
    const existingCount = await client.query('SELECT COUNT(*) FROM products');
    if (parseInt(existingCount.rows[0].count, 10) > 0) {
      console.log(`[Seed] products 表已有 ${existingCount.rows[0].count} 条数据，跳过插入`);
      await client.query('COMMIT');
      return;
    }

    // ─── 插入 25 条模拟商品 ──────────────────────────────────────
    console.log(`[Seed] 插入 ${PRODUCTS.length} 条模拟商品...`);

    for (const product of PRODUCTS) {
      await client.query(
        `INSERT INTO products (name, category, price, image_url, description)
         VALUES ($1, $2, $3, $4, $5)`,
        [product.name, product.category, product.price, product.image_url, product.description]
      );
    }

    await client.query('COMMIT');

    // ─── 验证结果 ────────────────────────────────────────────────
    const countResult = await client.query('SELECT COUNT(*) FROM products');
    const categoryResult = await client.query(
      'SELECT category, COUNT(*) as count FROM products GROUP BY category ORDER BY count DESC'
    );

    console.log('[Seed] 初始化完成!');
    console.log(`[Seed] 商品总数: ${countResult.rows[0].count}`);
    console.log('[Seed] 分类统计:');
    categoryResult.rows.forEach(row => {
      console.log(`  - ${row.category}: ${row.count} 件`);
    });

  } catch (err) {
    await client.query('ROLLBACK');
    console.error('[Seed] 初始化失败:', err.message);
    throw err;
  } finally {
    client.release();
    await pool.end();
  }
}

// 执行
seed()
  .then(() => {
    console.log('[Seed] 脚本执行成功');
    process.exit(0);
  })
  .catch((err) => {
    console.error('[Seed] 脚本执行失败:', err);
    process.exit(1);
  });
```
