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
