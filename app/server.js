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

// 管理员路由 - Tag-Based Cache Invalidation
const adminRoutes = require('./routes/admin');
app.use(adminRoutes);

// =============================================================================
// SSR 页面路由（使用 EJS 模板渲染）
// =============================================================================
const { query: dbQuery } = require('./db');

// 首页 — 展示推荐商品
app.get('/', async (req, res) => {
  try {
    const result = await dbQuery('SELECT * FROM products ORDER BY created_at DESC LIMIT 8');
    res.render('index', {
      currentPage: 'home',
      products: result.rows,
      title: '首页'
    });
  } catch (err) {
    // 数据库未就绪时使用空数据渲染
    res.render('index', {
      currentPage: 'home',
      products: [],
      title: '首页'
    });
  }
});

// 商品列表页
app.get('/products', async (req, res) => {
  try {
    const page = Math.max(1, parseInt(req.query.page, 10) || 1);
    const limit = 12;
    const offset = (page - 1) * limit;
    const category = req.query.category || null;

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

    sql += ` ORDER BY created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);

    const [productsResult, countResult, categoriesResult] = await Promise.all([
      dbQuery(sql, params),
      dbQuery(countSql, countParams),
      dbQuery('SELECT DISTINCT category FROM products ORDER BY category')
    ]);

    const total = parseInt(countResult.rows[0].count, 10);

    res.render('products', {
      currentPage: 'products',
      products: productsResult.rows,
      categories: categoriesResult.rows.map(r => r.category),
      currentCategory: category,
      pagination: {
        currentPage: page,
        totalPages: Math.ceil(total / limit),
        total
      },
      title: '商品列表'
    });
  } catch (err) {
    res.render('products', {
      currentPage: 'products',
      products: [],
      categories: [],
      currentCategory: null,
      pagination: { currentPage: 1, totalPages: 0, total: 0 },
      title: '商品列表'
    });
  }
});

// 商品详情页
app.get('/products/:id', async (req, res) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (isNaN(id)) return res.status(404).render('product-detail', { currentPage: 'products', product: null, title: '商品不存在' });

    const result = await dbQuery('SELECT * FROM products WHERE id = $1', [id]);
    if (result.rows.length === 0) {
      return res.status(404).render('product-detail', { currentPage: 'products', product: null, title: '商品不存在' });
    }

    res.render('product-detail', {
      currentPage: 'products',
      product: result.rows[0],
      title: result.rows[0].name
    });
  } catch (err) {
    res.render('product-detail', { currentPage: 'products', product: null, title: '商品详情' });
  }
});

// 购物车页
app.get('/cart', (req, res) => {
  res.render('cart', { currentPage: 'cart', title: '购物车' });
});

// 登录/注册页
app.get('/login', (req, res) => {
  res.render('login', { currentPage: 'login', title: '登录' });
});

// 调试页
app.get('/debug', (req, res) => {
  res.render('debug', {
    currentPage: 'debug',
    title: '调试信息',
    traceId: req.traceId,
    isNewUser: req.isNewUser,
    headers: req.headers,
    cookies: req.cookies,
    method: req.method,
    originalUrl: req.originalUrl,
    protocol: req.protocol,
    hostname: req.hostname,
    clientIp: req.ip
  });
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
