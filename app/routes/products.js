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
//
// Tag-Based Invalidation:
//   响应中设置 Cache-Tag header，Lambda@Edge (Origin Response) 会拦截并写入 DynamoDB
//   tag 格式: product-list, product-{id}, category-{category}, product-detail
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
 *
 * Cache-Tag: product-list, category-{category}, product-{id} (前 20 个)
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

    // 构建 Cache-Tag header（Tag-Based Invalidation）
    // - product-list: 任何商品变更时可失效整个列表
    // - category-{category}: 按分类失效（如果指定了分类筛选）
    // - product-{id}: 单个商品更新时也能失效包含它的列表（最多前 20 个）
    const cacheTags = ['product-list'];
    if (category) {
      // HTTP header 不允许非 ASCII，使用 encodeURIComponent 编码中文分类名
      cacheTags.push(`category-${encodeURIComponent(category)}`);
    }
    productsResult.rows.slice(0, 20).forEach(p => {
      cacheTags.push(`product-${p.id}`);
    });
    try { res.set('Cache-Tag', cacheTags.join(', ')); } catch (e) { /* skip if header invalid */ }

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
 *
 * Cache-Tag: product-{id}, category-{category}, product-detail
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

    const product = result.rows[0];

    // 构建 Cache-Tag header（Tag-Based Invalidation）
    // - product-{id}: 更新单个商品时失效
    // - category-{category}: 更新整个分类时失效
    // - product-detail: 全局失效所有商品详情
    const cacheTags = [
      `product-${id}`,
      product.category ? `category-${encodeURIComponent(product.category)}` : null,
      'product-detail',
    ].filter(Boolean).join(', ');
    try { res.set('Cache-Tag', cacheTags); } catch (e) { /* skip if header invalid */ }

    res.json({
      product: product,
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
