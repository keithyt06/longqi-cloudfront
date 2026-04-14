#!/bin/bash
set -ex

# 设置环境变量（cloud-init on Ubuntu 24.04 需要）
export HOME=/root
export DEBIAN_FRONTEND=noninteractive

# 日志输出到文件和 console
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting Unice Demo Platform setup ==="
echo "Timestamp: $(date)"

# =============================================================================
# 1. 更新系统包
# =============================================================================
echo "=== Updating system packages ==="
apt-get update
apt-get upgrade -y

# 安装基础工具
apt-get install -y curl wget git jq

# =============================================================================
# 2. 安装 Node.js 20 (via NodeSource)
# =============================================================================
echo "=== Installing Node.js 20 ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# =============================================================================
# 3. 安装 pm2（进程管理器）
# =============================================================================
echo "=== Installing pm2 ==="
npm install -g pm2

# =============================================================================
# 4. 创建应用目录和环境配置
# =============================================================================
echo "=== Setting up application ==="
APP_DIR="/opt/unice-app"
mkdir -p $APP_DIR

# 写入环境配置文件（Terraform 模板变量在此处已被替换为实际值）
cat > $APP_DIR/.env <<'ENVEOF'
NODE_ENV=production
PORT=3000
AWS_REGION=${region}
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
COGNITO_USER_POOL_ID=${cognito_user_pool_id}
COGNITO_CLIENT_ID=${cognito_client_id}
DYNAMODB_TABLE_NAME=${dynamodb_table_name}
S3_BUCKET_NAME=${s3_bucket_name}
ENVEOF

# =============================================================================
# 5. 创建占位 Express 应用
# =============================================================================
# 完整应用代码（app/ 目录）将在后续部署步骤中同步
# 此处创建最小可用应用，确保 ALB 健康检查通过

cat > $APP_DIR/package.json <<'PKGEOF'
{
  "name": "unice-demo",
  "version": "1.0.0",
  "description": "CloudFront Demo Platform - Unice",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "dotenv": "^16.4.0"
  }
}
PKGEOF

cat > $APP_DIR/server.js <<'APPEOF'
require('dotenv').config();
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// 健康检查端点（ALB Target Group 使用）
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    traceId: req.headers['x-trace-id'] || 'none',
    version: '1.0.0',
    env: {
      region: process.env.AWS_REGION || 'unknown',
      dbConfigured: !!process.env.DB_HOST,
      cognitoConfigured: !!process.env.COGNITO_USER_POOL_ID
    }
  });
});

// 调试端点 - 返回所有 request headers
app.get('/api/debug', (req, res) => {
  res.json({
    headers: req.headers,
    ip: req.ip,
    method: req.method,
    url: req.url,
    protocol: req.protocol,
    hostname: req.hostname,
    timestamp: new Date().toISOString()
  });
});

// 延迟端点 - 模拟慢响应（测试 CloudFront Origin Timeout）
app.get('/api/delay/:ms', (req, res) => {
  const ms = parseInt(req.params.ms) || 1000;
  const capped = Math.min(ms, 30000); // 最大 30 秒
  setTimeout(() => {
    res.json({
      delayed: capped,
      timestamp: new Date().toISOString()
    });
  }, capped);
});

// 默认路由
app.get('/', (req, res) => {
  res.send([
    '<h1>Unice Demo - CloudFront Demo Platform</h1>',
    '<p>Platform is running. Full app deployment pending.</p>',
    '<ul>',
    '<li><a href="/api/health">/api/health</a> - Health check</li>',
    '<li><a href="/api/debug">/api/debug</a> - Debug headers</li>',
    '<li><a href="/api/delay/1000">/api/delay/1000</a> - 1s delay test</li>',
    '</ul>'
  ].join('\n'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('Unice Demo server running on port ' + PORT);
});
APPEOF

# =============================================================================
# 6. 安装依赖并启动应用
# =============================================================================
cd $APP_DIR
npm install --production

# 使用 pm2 启动应用
pm2 start server.js --name unice-app
pm2 save

# 配置 pm2 开机自启
pm2 startup systemd -u root --hp /root

# =============================================================================
# 7. 健康检查
# =============================================================================
echo "=== Final health check ==="
sleep 3

if curl -s http://127.0.0.1:3000/api/health | grep -q '"status":"ok"'; then
    echo "Health check: PASSED"
else
    echo "Health check: FAILED"
    pm2 logs unice-app --lines 20 || true
fi

echo "=== Unice Demo Platform setup completed ==="
echo "Timestamp: $(date)"
