# 12 - CloudFront Tag-Based Cache Invalidation: 基于标签的精准缓存失效

> **目标**: 配置 Lambda@Edge + DynamoDB 实现基于语义标签的缓存失效，替代传统的路径通配符失效方式。当商品数据更新时，只需指定标签（如 `product-123`），系统自动找到所有关联的缓存路径并失效。
>
> **预计时间**: 45-60 分钟
>
> **前提条件**:
> - 已创建 CloudFront Distribution（参考 Hands-on 01）
> - 已配置 Cache Behavior（参考 Hands-on 02）
> - 已部署 Express 应用（/api/products 接口正常工作）
> - 具备 Lambda@Edge 部署经验（了解 us-east-1 部署要求）
> - IAM 权限: Lambda、DynamoDB、CloudFront 管理权限

---

## 传统失效 vs 标签失效

### 问题场景

假设商品 ID=123（分类: hair）更新了价格。需要失效的缓存路径包括:

| 缓存路径 | 说明 |
|----------|------|
| `/api/products/123` | 商品详情 API |
| `/api/products?page=1` | 包含该商品的列表第 1 页 |
| `/api/products?page=1&category=hair` | 分类筛选页 |
| `/api/products?category=hair&sort=price` | 分类 + 排序 |
| `/api/products?page=2&category=hair&sort=price` | 分类 + 排序 + 分页 |
| `/products/123` | 商品详情 SSR 页面 |
| ... | Query String 组合可能有数十种 |

### 对比

| 维度 | 传统路径失效 | 标签失效 |
|------|------------|---------|
| **失效方式** | 指定精确路径或通配符 `/*` | 指定语义标签 `product-123` |
| **精确度** | 通配符 `/*` 会清除所有缓存；精确路径需列举每个 URL | 只清除与标签关联的 URL，其他缓存不受影响 |
| **Query String** | 每种 Query String 组合是独立的缓存键，需逐一列举 | 自动追踪所有 Query String 变体 |
| **维护成本** | 需要应用层维护 URL→缓存路径映射 | tag 映射自动维护（Lambda@Edge 写入 DynamoDB） |
| **API 调用** | 1 次 CreateInvalidation + 列举所有路径 | 1 次 API 调用 + 自动查询 DynamoDB |
| **适用场景** | 路径少、Query String 简单的静态站 | 动态 API、Query String 组合多的电商/内容站 |
| **CloudFront 限制** | 每次失效最多 3000 路径，每月 1000 次免费 | 相同，但路径自动发现，不怕遗漏 |

### 标签失效优势示例

```
传统方式（需要知道每个精确路径）:
POST /cloudfront/2020-05-31/distribution/E1EXAMPLE/invalidation
Paths: [
  "/api/products/123",
  "/api/products?page=1",
  "/api/products?page=1&category=hair",
  "/api/products?category=hair&sort=price",
  "/api/products?page=2&category=hair&sort=price",
  ... (可能还有几十条)
]

标签方式（只需知道语义标签）:
POST /api/admin/invalidate-tag
{ "tag": "product-123" }
→ 系统自动找到所有关联 URL 并失效
```

---

## 架构图

```
                    ┌──────────────────────────────────────────────────────┐
                    │                 CloudFront Distribution              │
                    │               unice.keithyu.cloud                   │
                    │                                                      │
                    │  Behavior: /api/products*                            │
                    │    ├─ Cache Policy: ProductCache (3600s)             │
                    │    └─ Lambda@Edge: Origin Response                   │
                    │         ↓ (仅 Cache Miss 触发)                       │
                    └──────────┬──────────────────────────┬────────────────┘
                               │                          │
                    ┌──────────▼──────────┐    ┌──────────▼──────────┐
                    │  VPC Origin → ALB   │    │  Lambda@Edge        │
                    │  → EC2 Express      │    │  Origin Response    │
                    │                     │    │                     │
                    │  响应 headers:       │    │  1. 解析 Cache-Tag  │
                    │  Cache-Tag:         │    │  2. 写入 DynamoDB   │
                    │    product-123,     │    │  3. 删除 header     │
                    │    category-hair    │    │  4. 返回响应        │
                    └─────────────────────┘    └──────────┬──────────┘
                                                          │
                                               ┌──────────▼──────────┐
                                               │     DynamoDB        │
                                               │  unice-cache-tags   │
                                               │                     │
                                               │  PK: tag            │
                                               │  SK: url            │
                                               │  TTL: expire_at     │
                                               └──────────┬──────────┘
                                                          │
                          ┌───────────────────────────────┘
                          │ 管理员触发失效
                          │
               ┌──────────▼──────────┐
               │  POST /api/admin/   │
               │  invalidate-tag     │
               │  { tag: "product-   │
               │    123" }           │
               └──────────┬──────────┘
                          │
               ┌──────────▼──────────┐
               │  Invalidation       │
               │  Lambda             │
               │                     │
               │  1. Query DynamoDB  │
               │     (tag=product-   │
               │      123)           │
               │  2. 收集所有 URL    │
               │  3. CloudFront      │
               │     CreateInvali-   │
               │     dation          │
               └─────────────────────┘
```

---

## 步骤 1: 创建 DynamoDB 表

DynamoDB 表存储 tag → URL 的映射关系。每个缓存的 URL 可能关联多个 tag，每个 tag 下可能有多个 URL。

- [ ] 打开 **DynamoDB Console** → 点击 **Create table**
- [ ] 填写表配置:

| 参数 | 值 |
|------|-----|
| Table name | `unice-cache-tags` |
| Partition key | `tag` (String) |
| Sort key | `url` (String) |

- [ ] 展开 **Table settings** → 选择 **Customize settings**
- [ ] **Read/write capacity settings**: 选择 **On-demand**（按需模式，适合演示环境的不规则流量）
- [ ] 点击 **Create table**

### 启用 TTL

- [ ] 等待表状态变为 **Active**
- [ ] 点击表名进入详情 → 选择 **Additional settings** 标签页
- [ ] 在 **Time to Live (TTL)** 区域点击 **Turn on**
- [ ] TTL attribute 填写: `expire_at`
- [ ] 点击 **Turn on TTL**

> **说明**: TTL 启用后，DynamoDB 会自动删除 `expire_at` 时间戳过期的记录。通常在过期后 48 小时内删除（不是精确即时删除）。这能防止 tag 映射表无限增长。

---

## 步骤 2: 创建 Lambda@Edge 函数（Origin Response）

Lambda@Edge 必须部署在 **us-east-1** 区域。

- [ ] 切换到 **US East (N. Virginia) us-east-1** 区域
- [ ] 打开 **Lambda Console** → 点击 **Create function**
- [ ] 选择 **Author from scratch**
- [ ] 填写配置:

| 参数 | 值 |
|------|-----|
| Function name | `unice-cache-tag-origin-response` |
| Runtime | **Node.js 20.x** |
| Architecture | **x86_64**（Lambda@Edge 要求） |

- [ ] 展开 **Change default execution role** → 选择 **Create a new role with basic Lambda permissions**
- [ ] 点击 **Create function**

### 配置 IAM 权限

- [ ] 进入函数详情 → **Configuration** → **Permissions**
- [ ] 点击 Role name 链接（打开 IAM Console）
- [ ] 在 **Trust relationships** 标签页，点击 **Edit trust policy**
- [ ] 将信任策略修改为:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

- [ ] 点击 **Update policy**

- [ ] 在 **Permissions** 标签页，点击 **Add permissions** → **Create inline policy**
- [ ] 选择 **JSON** 编辑器，粘贴:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:ap-northeast-1:YOUR_ACCOUNT_ID:table/unice-cache-tags"
    }
  ]
}
```

> **注意**: 将 `YOUR_ACCOUNT_ID` 替换为你的 AWS 账号 ID。DynamoDB 表在 ap-northeast-1，但 Lambda@Edge 可以跨区域写入。

- [ ] Policy name 填写 `unice-cache-tag-dynamodb-write`
- [ ] 点击 **Create policy**

### 编写函数代码

- [ ] 返回 Lambda 函数 → **Code** 标签页
- [ ] 将默认文件重命名为 `index.mjs`（ESM 模块）
- [ ] 粘贴以下代码:

```javascript
// Lambda@Edge: Origin Response - Cache Tag 捕获
// 部署区域: us-east-1
// 触发: CloudFront Origin Response (仅 Cache Miss)

import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';

// 配置 - 根据实际环境修改
const DYNAMODB_REGION = 'ap-northeast-1';
const TABLE_NAME = 'unice-cache-tags';
const TAG_HEADER = 'cache-tag';
const TAG_DELIMITER = ',';
const TAG_TTL_SECONDS = 86400; // 24 小时

const dynamodb = new DynamoDBClient({ region: DYNAMODB_REGION });

export const handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;

  // 检查是否有 Cache-Tag header
  const tagHeader = response.headers[TAG_HEADER];
  if (!tagHeader || !tagHeader[0] || !tagHeader[0].value) {
    return response;
  }

  const tagValue = tagHeader[0].value;
  const uri = request.uri;
  const querystring = request.querystring;
  const fullUrl = querystring ? `${uri}?${querystring}` : uri;

  // 解析 tag 列表
  const tags = tagValue.split(TAG_DELIMITER).map(t => t.trim()).filter(t => t.length > 0);

  // 计算 TTL
  const expireAt = TAG_TTL_SECONDS > 0
    ? Math.floor(Date.now() / 1000) + TAG_TTL_SECONDS
    : 0;

  // 并行写入 DynamoDB
  const writePromises = tags.map(tag => {
    const params = {
      TableName: TABLE_NAME,
      Item: {
        tag: { S: tag },
        url: { S: fullUrl },
        uri: { S: uri },
        querystring: { S: querystring || '' },
        updated_at: { S: new Date().toISOString() },
        distribution_id: { S: event.Records[0].cf.config.distributionId },
      },
    };
    if (expireAt > 0) {
      params.Item.expire_at = { N: String(expireAt) };
    }
    return dynamodb.send(new PutItemCommand(params));
  });

  try {
    await Promise.all(writePromises);
  } catch (err) {
    console.error('DynamoDB write error:', err);
    // 不阻塞响应
  }

  // 删除 tag header，不暴露给客户端
  delete response.headers[TAG_HEADER];

  return response;
};
```

- [ ] 点击 **Deploy**

### 配置函数属性

- [ ] **Configuration** → **General configuration** → **Edit**

| 参数 | 值 |
|------|-----|
| Memory | **128 MB** |
| Timeout | **30 seconds**（Lambda@Edge 最大 30 秒） |

- [ ] 点击 **Save**

### 发布版本

Lambda@Edge 必须使用已发布的版本（不能使用 $LATEST）。

- [ ] **Actions** → **Publish new version**
- [ ] Description 填写: `v1 - Initial release`
- [ ] 点击 **Publish**
- [ ] 记录版本 ARN，格式: `arn:aws:lambda:us-east-1:ACCOUNT_ID:function:unice-cache-tag-origin-response:1`

---

## 步骤 3: 在 CloudFront Behavior 中绑定 Lambda@Edge

- [ ] 打开 **CloudFront Console** → 选择你的 Distribution
- [ ] 选择 **Behaviors** 标签页
- [ ] 找到 `/api/products*` 的 Behavior → 点击 **Edit**
- [ ] 滚动到 **Function associations** 区域
- [ ] 在 **Origin response** 行:

| 参数 | 值 |
|------|-----|
| Function type | **Lambda@Edge** |
| Function ARN/Name | 粘贴步骤 2 中记录的版本 ARN |

- [ ] 点击 **Save changes**
- [ ] 等待 Distribution 状态变为 **Deployed**（约 3-5 分钟）

> **说明**: Lambda@Edge Origin Response 仅在 Cache Miss 时触发。如果 CloudFront 边缘节点已有缓存，直接返回缓存内容，不会触发 Lambda@Edge。这意味着只有首次请求（或缓存过期后的请求）会写入 DynamoDB。

---

## 步骤 4: 修改 Express 应用添加 Cache-Tag Header

确保 Express 应用在商品 API 响应中包含 `Cache-Tag` header。

- [ ] SSH 到 EC2 实例
- [ ] 编辑 `app/routes/products.js`

在 GET `/api/products/:id` 路由中，`res.json()` 之前添加:

```javascript
// 添加 Cache-Tag header（Lambda@Edge 会捕获并存入 DynamoDB）
const cacheTags = [
  `product-${id}`,
  product.category ? `category-${product.category}` : null,
  'product-detail',
].filter(Boolean).join(', ');

res.set('Cache-Tag', cacheTags);
```

在 GET `/api/products` 路由中，`res.json()` 之前添加:

```javascript
// 添加 Cache-Tag header
const cacheTags = ['product-list'];
if (category) cacheTags.push(`category-${category}`);
products.items.slice(0, 20).forEach(p => cacheTags.push(`product-${p.id}`));

res.set('Cache-Tag', cacheTags.join(', '));
```

- [ ] 重启 Express 应用: `pm2 restart unice`

---

## 步骤 5: 验证 Tag 注入流程

### 5.1 触发 Cache Miss 使 Lambda@Edge 执行

- [ ] 清除现有缓存（确保下次请求是 Cache Miss）:

```bash
# 失效所有商品 API 缓存
aws cloudfront create-invalidation \
  --distribution-id YOUR_DIST_ID \
  --paths "/api/products*"
```

- [ ] 等待失效完成:

```bash
aws cloudfront get-invalidation \
  --distribution-id YOUR_DIST_ID \
  --id INVALIDATION_ID
```

### 5.2 发起请求触发 tag 注入

- [ ] 请求商品详情:

```bash
# 请求商品 ID=1
curl -s -D - "https://unice.keithyu.cloud/api/products/1" | head -20
```

预期响应 headers 中 **不包含** `Cache-Tag`（已被 Lambda@Edge 删除），但包含:
```
X-Cache: Miss from cloudfront
```

- [ ] 再次请求确认缓存命中:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/1" | head -20
```

预期响应:
```
X-Cache: Hit from cloudfront
```

### 5.3 验证 DynamoDB 写入

- [ ] 打开 **DynamoDB Console** → 选择 `unice-cache-tags` 表 → **Explore table items**
- [ ] 应能看到类似记录:

| tag | url | uri | updated_at | expire_at |
|-----|-----|-----|------------|-----------|
| product-1 | /api/products/1 | /api/products/1 | 2026-04-14T10:30:00Z | 1713186600 |
| category-hair | /api/products/1 | /api/products/1 | 2026-04-14T10:30:00Z | 1713186600 |
| product-detail | /api/products/1 | /api/products/1 | 2026-04-14T10:30:00Z | 1713186600 |

- [ ] 请求商品列表触发更多 tag 注入:

```bash
curl -s "https://unice.keithyu.cloud/api/products?page=1&category=hair" > /dev/null
curl -s "https://unice.keithyu.cloud/api/products?page=1" > /dev/null
curl -s "https://unice.keithyu.cloud/api/products?category=hair&sort=price" > /dev/null
```

- [ ] 刷新 DynamoDB Console，确认新记录已写入

---

## 步骤 6: 测试标签失效

### 6.1 确认缓存存在

- [ ] 先确认缓存命中:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/1" 2>&1 | grep "X-Cache"
# 预期: X-Cache: Hit from cloudfront
```

### 6.2 调用标签失效 API

- [ ] 通过 admin API 触发失效:

```bash
curl -X POST "https://unice.keithyu.cloud/api/admin/invalidate-tag" \
  -H "Content-Type: application/json" \
  -d '{"tag": "product-1"}'
```

预期响应:

```json
{
  "message": "Tag-based invalidation completed",
  "tags": ["product-1"],
  "total_urls": 3,
  "batches": [
    {
      "invalidation_id": "I3XXXXXX",
      "paths_count": 3,
      "status": "InProgress"
    }
  ],
  "invalidated_urls": [
    "/api/products/1",
    "/api/products?page=1",
    "/api/products?page=1&category=hair"
  ],
  "mode": "direct-lambda"
}
```

### 6.3 验证缓存已失效

- [ ] 等待 1-2 秒后再次请求:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/1" 2>&1 | grep "X-Cache"
# 预期: X-Cache: Miss from cloudfront (缓存已被清除)
```

- [ ] 确认其他商品的缓存不受影响:

```bash
curl -s -D - "https://unice.keithyu.cloud/api/products/2" 2>&1 | grep "X-Cache"
# 预期: X-Cache: Hit from cloudfront (product-2 的缓存未被影响)
```

### 6.4 测试按分类失效

- [ ] 失效整个 hair 分类:

```bash
curl -X POST "https://unice.keithyu.cloud/api/admin/invalidate-tag" \
  -H "Content-Type: application/json" \
  -d '{"tag": "category-hair"}'
```

- [ ] 验证 hair 分类的所有缓存路径均已失效

---

## 步骤 7: 查看管理状态

### 7.1 查看 tag 映射

- [ ] 查看特定 tag 的 URL 映射:

```bash
curl -s "https://unice.keithyu.cloud/api/admin/cache-tags?tag=product-1" | jq .
```

### 7.2 查看失效历史

- [ ] 查看 CloudFront 最近的失效记录:

```bash
curl -s "https://unice.keithyu.cloud/api/admin/invalidation-status" | jq .
```

---

## 步骤 8: 查看 Lambda@Edge 日志

Lambda@Edge 的日志存储在函数执行所在的边缘区域的 CloudWatch Logs 中。

- [ ] 打开 **CloudWatch Console**
- [ ] 切换到你测试时请求实际路由到的区域（例如从东京访问可能是 ap-northeast-1）
- [ ] **Log groups** → 搜索 `/aws/lambda/us-east-1.unice-cache-tag-origin-response`
- [ ] 查看最新的 log stream，确认 tag 解析和 DynamoDB 写入日志

> **注意**: Lambda@Edge 日志分布在各边缘区域，不一定在 us-east-1。需要在请求实际到达的区域查找日志。

---

## 常见问题

### Q1: Lambda@Edge 部署后 CloudFront Distribution 一直在 "In Progress" 状态

**原因**: Lambda@Edge 的首次关联或版本更新需要全球传播，通常需要 5-15 分钟。

**解决**: 耐心等待。可以在 CloudFront Console 查看 Distribution 状态。如果超过 30 分钟仍未完成，检查:
- Lambda 函数是否在 us-east-1
- 是否使用了已发布的版本（不是 $LATEST）
- IAM Role 的信任策略是否包含 `edgelambda.amazonaws.com`

### Q2: DynamoDB 中没有看到 tag 记录

**可能原因**:
1. **CloudFront 返回缓存命中**: 只有 Cache Miss 时才触发 Lambda@Edge Origin Response。先执行失效操作清除缓存。
2. **Express 没有返回 Cache-Tag header**: 使用 curl 直接请求源站确认:
   ```bash
   curl -s -D - "http://INTERNAL_ALB_DNS/api/products/1" | grep -i cache-tag
   ```
3. **Lambda@Edge 执行错误**: 检查 CloudWatch Logs（注意区域）。
4. **IAM 权限不足**: 确认 Lambda@Edge Role 有 DynamoDB PutItem 权限。

### Q3: Cache-Tag header 出现在浏览器 DevTools 中

**原因**: Lambda@Edge 代码中的 `delete response.headers[TAG_HEADER]` 没有正确执行。

**检查**: 确认 TAG_HEADER 变量值为小写 `cache-tag`（CloudFront 的 Origin Response 事件中 header 名均为小写）。

### Q4: 失效请求返回 "No cached URLs found"

**可能原因**:
1. DynamoDB 记录已被 TTL 自动删除（默认 24 小时后过期）
2. tag 名称不匹配（大小写敏感）: 确认请求中的 tag 与 Express 设置的 Cache-Tag 值完全一致
3. DynamoDB 查询区域不正确

### Q5: CloudFront 限制相关

| 限制 | 值 | 说明 |
|------|-----|------|
| 每次失效最大路径数 | 3000 | 超过需分批提交 |
| 同时进行的失效请求 | 3000 路径 | 排队等待 |
| 每月免费失效数 | 1000 路径 | 超过 $0.005/路径 |
| 通配符失效 | 支持 `/*` | 但 tag 方式更精确 |

### Q6: Lambda@Edge 的限制

| 限制 | Origin Response | 说明 |
|------|----------------|------|
| 执行超时 | 30 秒 | DynamoDB 写入通常 < 100ms |
| 内存 | 128 MB - 10 GB | 128 MB 足够 |
| 代码包大小 | 50 MB | 本函数 < 5KB |
| 不能访问 VPC | 是 | DynamoDB 通过公网端点访问 |
| 必须在 us-east-1 | 是 | 但会全球复制到边缘节点 |

### Q7: DynamoDB 费用估算

对于演示环境（每天约 1000 次 Cache Miss、平均每次 3 个 tag）:

| 项目 | 估算 |
|------|------|
| 写入 (PutItem) | ~3000 次/天 × $1.25/百万 = ~$0.004/天 |
| 读取 (Query) | ~100 次/天 × $0.25/百万 = ~$0.00003/天 |
| 存储 | ~100KB (极少) ≈ $0 |
| **月总计** | **< $0.15** |
