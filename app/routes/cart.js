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

  // 参数校验: productId 必填，name/price 仅新商品必填
  if (!productId) {
    return res.status(400).json({
      error: '缺少必填字段: productId',
      traceId,
      timestamp: new Date().toISOString()
    });
  }

  const numQuantity = Math.max(1, parseInt(quantity, 10) || 1);

  // 获取或创建购物车
  if (!carts.has(traceId)) {
    carts.set(traceId, []);
  }
  const cart = carts.get(traceId);

  // 检查是否已存在相同商品
  const existingIndex = cart.findIndex(item => item.productId === String(productId));

  if (existingIndex >= 0) {
    // 已存在：直接设置数量（支持前端 updateCartItem 调用）
    cart[existingIndex].quantity = numQuantity;
    cart[existingIndex].updatedAt = new Date().toISOString();
  } else {
    // 不存在：添加新商品（name 和 price 必填）
    if (!name || price === undefined) {
      return res.status(400).json({
        error: '新增商品需要 name 和 price 字段',
        traceId,
        timestamp: new Date().toISOString()
      });
    }
    const numPrice = parseFloat(price);
    if (isNaN(numPrice) || numPrice < 0) {
      return res.status(400).json({
        error: '无效的价格',
        traceId,
        timestamp: new Date().toISOString()
      });
    }
    cart.push({
      productId: String(productId),
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
