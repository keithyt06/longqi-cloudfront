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
