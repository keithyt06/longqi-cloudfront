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
