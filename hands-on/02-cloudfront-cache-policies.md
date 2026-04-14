# 02 - CloudFront 缓存策略：Cache Key 与自定义 Policy

> **目标**: 理解 CloudFront Cache Key 的组成，创建自定义 Cache Policy（ProductCache 3600s / PageCache 60s）和 Origin Request Policy，验证缓存命中行为。
>
> **预计时间**: 20-30 分钟
>
> **前提条件**:
> - 已完成文档 01（Distribution 已创建并部署）

---

## 概念说明：Cache Key 的组成

CloudFront 使用 **Cache Key** 来标识缓存中的每个对象。Cache Key 决定了"什么条件下认为两个请求是同一个资源"。

```
Cache Key = URL Path + 选定的 Query Strings + 选定的 Headers + 选定的 Cookies
```

**核心原则**：
- Cache Key 中包含的元素越多 → 缓存粒度越细 → 命中率越低
- Cache Key 中包含的元素越少 → 缓存粒度越粗 → 命中率越高

**Cache Policy vs Origin Request Policy**：
| | Cache Policy | Origin Request Policy |
|---|---|---|
| 作用 | 决定哪些元素组成 Cache Key | 决定哪些元素转发给 Origin |
| 对缓存命中率的影响 | 直接影响 | 不影响 |
| 典型使用 | 控制缓存粒度 | Origin 需要但不应影响缓存的数据 |

> **关键区分**：如果 Origin 需要 `Accept-Language` header 来返回不同语言的内容，但你不想为每种语言单独缓存，就把它放在 Origin Request Policy（转发但不加入 Cache Key）。反之，如果确实需要按语言分别缓存，就放在 Cache Policy。

---

## 步骤 1: 创建自定义 Cache Policy — ProductCache (3600s)

用于 `/api/products*` 路径。商品数据按 Query String 区分（page/category/sort），缓存 1 小时。

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Policies** → **Cache** → **Create cache policy**

| 参数 | 值 |
|------|-----|
| Name | `ProductCache` |
| Description | `Product API cache - 1 hour TTL, cache key includes all query strings` |
| **TTL settings** | |
| Minimum TTL | `60` (秒) |
| Maximum TTL | `3600` (秒) |
| Default TTL | `3600` (秒) |
| **Cache key settings** | |
| Headers | **None** |
| Cookies | **None** |
| Query strings | **All** |
| **Compression support** | |
| Gzip | **Enabled** |
| Brotli | **Enabled** |

- [ ] 点击 **Create**

> **为什么 Query strings 选 All**：商品列表 API 使用 `/api/products?page=1&category=shoes&sort=price` 格式。不同的 page/category/sort 组合应该有独立缓存，所以把所有 Query String 都加入 Cache Key。

---

## 步骤 2: 创建自定义 Cache Policy — PageCache (60s)

用于 Default (*) 路径。SSR 页面短缓存 60 秒，仅转发 `x-trace-id` 和 `aws-waf-token` 两个 Cookie。

- [ ] **Policies** → **Cache** → **Create cache policy**

| 参数 | 值 |
|------|-----|
| Name | `PageCache` |
| Description | `SSR page cache - 60s TTL, include trace and WAF cookies` |
| **TTL settings** | |
| Minimum TTL | `0` (秒) |
| Maximum TTL | `60` (秒) |
| Default TTL | `60` (秒) |
| **Cache key settings** | |
| Headers | **Include the following headers** → 添加 `Accept`, `Accept-Language` |
| Cookies | **Include the following cookies** → 添加 `x-trace-id`, `aws-waf-token` |
| Query strings | **All** |
| **Compression support** | |
| Gzip | **Enabled** |
| Brotli | **Enabled** |

- [ ] 点击 **Create**

> **为什么只转发 2 个 Cookie**：浏览器可能携带大量 Cookie（analytics、session 等）。如果全部加入 Cache Key，几乎每个用户的请求都会成为唯一的缓存条目，命中率接近 0%。仅包含业务必需的 `x-trace-id`（用户追踪）和 `aws-waf-token`（WAF 验证）。

---

## 步骤 3: 创建 Origin Request Policy（可选）

如果 Origin 需要额外的 Header/Cookie 但这些不应影响缓存，就需要自定义 Origin Request Policy。

对于本平台，大部分场景使用 AWS 托管的 `AllViewer` 策略即可（转发所有 Viewer 的 Header/Cookie/Query String）。

查看已有托管策略：

- [ ] 打开 **CloudFront Console** → **Policies** → **Origin request**
- [ ] 确认以下托管策略可用：

| 策略名称 | 转发内容 | 使用场景 |
|----------|----------|----------|
| `AllViewer` | 所有 Header + Cookie + Query String | API 路由需要完整请求信息 |
| `CORS-S3Origin` | CORS 相关 Header | S3 跨域资源 |
| `UserAgentRefererHeaders` | User-Agent + Referer | 简单日志/统计场景 |

> **本平台策略**：`/api/*` Behavior 使用 `AllViewer`（API 需要完整信息），S3 Behavior 不设 Origin Request Policy（静态资源不需要额外 header）。

---

## 步骤 4: 将自定义 Cache Policy 绑定到 Behavior

### 4.1 绑定 ProductCache 到 `/api/products*`

- [ ] 打开 Distribution → **Behaviors** → 选择 `/api/products*` → **Edit**
- [ ] 修改 Cache policy 为 `ProductCache`
- [ ] Origin request policy 保持 `AllViewer`
- [ ] 点击 **Save changes**

### 4.2 绑定 PageCache 到 Default (*)

- [ ] 选择 **Default (*)** → **Edit**
- [ ] 修改 Cache policy 为 `PageCache`
- [ ] Origin request policy 保持 `AllViewer`
- [ ] 点击 **Save changes**

- [ ] 等待 Distribution 状态变为 **Deployed**

---

## 步骤 5: 验证缓存行为

### 5.1 验证 ProductCache（商品 API）

```bash
# 第一次请求 - 应该是 Miss
curl -sI https://unice.keithyu.cloud/api/products?page=1&category=all | grep -i x-cache

# 第二次请求 - 应该是 Hit
curl -sI https://unice.keithyu.cloud/api/products?page=1&category=all | grep -i x-cache

# 不同 Query String - 应该是 Miss（不同的 Cache Key）
curl -sI https://unice.keithyu.cloud/api/products?page=2&category=all | grep -i x-cache
```

- [ ] 确认第一次请求 `X-Cache: Miss from cloudfront`
- [ ] 确认第二次请求 `X-Cache: Hit from cloudfront`
- [ ] 确认不同 Query String 产生 `Miss`（说明 Query String 确实加入了 Cache Key）

### 5.2 验证 PageCache（SSR 页面）

```bash
# 第一次请求
curl -sI https://unice.keithyu.cloud/ | grep -i x-cache

# 第二次请求（60 秒内）
curl -sI https://unice.keithyu.cloud/ | grep -i x-cache

# 等待 60 秒后请求 - 缓存已过期
sleep 65
curl -sI https://unice.keithyu.cloud/ | grep -i x-cache
```

- [ ] 确认 60 秒内第二次请求为 `Hit`
- [ ] 确认 60 秒后请求为 `Miss`（缓存已过期）

### 5.3 验证 CachingDisabled（购物车/用户 API）

```bash
# 多次请求 - 始终是 Miss（不缓存）
curl -sI https://unice.keithyu.cloud/api/debug | grep -i x-cache
curl -sI https://unice.keithyu.cloud/api/debug | grep -i x-cache
```

- [ ] 确认每次请求都是 `Miss from cloudfront`（CachingDisabled 生效）

### 5.4 查看完整缓存相关 Header

```bash
# 完整 Header 检查
curl -sI https://unice.keithyu.cloud/api/products?page=1 | grep -iE '(x-cache|age|cache-control|x-amz)'
```

- [ ] `X-Cache`: 显示 Hit/Miss 状态
- [ ] `Age`: 对象在缓存中的存活时间（秒），仅 Hit 时出现
- [ ] `X-Amz-Cf-Pop`: 响应的 CloudFront PoP 节点（如 `NRT51-C3` = 东京）

---

## Behavior 与缓存策略对照表

| Path Pattern | Origin | Cache Policy | TTL | Query String | Cookie | 使用场景 |
|---|---|---|---|---|---|---|
| `/static/*` | S3 (OAC) | CachingOptimized | 86400s (24h) | 无 | 无 | CSS/JS/字体 |
| `/images/*` | S3 (OAC) | CachingOptimized | 86400s (24h) | 无 | 无 | 商品图片 |
| `/api/products*` | ALB (VPC) | ProductCache | 3600s (1h) | All | 无 | 商品列表 |
| `/api/*` | ALB (VPC) | CachingDisabled | 0 | All | All | 购物车/用户/订单/调试 |
| `Default (*)` | ALB (VPC) | PageCache | 60s | All | x-trace-id, aws-waf-token | SSR 页面 |

---

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 始终是 Miss，永远不 Hit | Cache Policy 的 TTL 设为 0，或 Origin 返回 `Cache-Control: no-store` | 检查 Cache Policy TTL 设置；用 `curl -sI` 查看 Origin 返回的 `Cache-Control` header |
| 不同用户看到相同缓存内容 | Cookie 未加入 Cache Key | 确认需要按用户区分的 Behavior 使用 CachingDisabled |
| Cache Policy 创建后看不到 | Console 页面缓存 | 刷新页面，或直接在 Behavior 编辑页面的下拉菜单中搜索 |
| Query String 变更后仍返回旧内容 | Query String 未加入 Cache Key | 检查 Cache Policy 的 Query strings 设置是否为 All |
