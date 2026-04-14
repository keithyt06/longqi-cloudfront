# CloudFront 全功能演示平台 - 设计规格书

> **域名**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京) | **Profile**: `default`
>
> **文档版本**: v1.1 | **日期**: 2026-04-14 | **作者**: Keith (AWS SA)

---

## 1. 项目概述

### 1.1 背景与目标

Amazon CloudFront 是 AWS 的全球内容分发网络 (CDN) 服务，拥有超过 600 个全球边缘节点（PoP）。随着 CloudFront 功能的持续演进——从基础的静态内容加速，到 VPC Origin、Continuous Deployment、Bot Control 等高级功能——客户在实际落地时往往缺乏一个完整的参考架构来理解各功能之间的协同工作方式。

本项目旨在构建一个 **功能性电商模拟网站**，参考 [unice.com](https://www.unice.com) 的路径结构，作为 CloudFront 全栈功能的演示和测试平台。通过这个平台，AWS SA 可以：

- **向客户实时演示** CloudFront 各项功能的配置与效果
- **提供 hands-on 文档** 指导客户在 AWS Console 中逐步手动配置
- **验证新功能** 如 VPC Origin、Continuous Deployment 在真实场景下的表现
- **测试安全策略** 包括 WAF Bot Control + JS SDK、签名 URL、地理限制等

### 1.2 技术选型概要

本平台采用 **S3（静态内容）+ EC2 Express（动态 API）** 双源架构，通过 CloudFront 统一入口，配合多路径多策略的 Cache Behavior 配置，全面覆盖以下 CloudFront 核心功能：

| 功能类别 | 具体功能 |
|---------|---------|
| **内容分发** | 多源路由（S3 + ALB）、缓存策略、自定义错误页面 |
| **边缘计算** | CloudFront Functions（URL 重写、A/B 测试、地理重定向） |
| **安全防护** | WAF（基础规则 + Bot Control + JS SDK）、地理限制、签名 URL/Cookie、OAC |
| **网络架构** | VPC Origin（连接内网 ALB，零公网暴露） |
| **发布管理** | Continuous Deployment（Staging 分发 + 流量灰度切换） |
| **缓存管理** | Tag-Based Invalidation（基于内容标签的精准缓存失效，Lambda@Edge + DynamoDB 映射） |
| **用户追踪** | UUID 链路追踪（EC2 端生成，CloudFront 透传，跨设备统一） |
| **可观测性** | CloudFront Standard Logging、Response Headers Policy |

### 1.3 配套文档

项目配套 **12 篇 hands-on 实操文档**，每篇聚焦一个 CloudFront 功能维度，包含 AWS Console 截图步骤、配置参数说明、验证方法和常见问题排查。文档面向具备基础 AWS 经验的技术人员，可作为客户自助学习材料或 Workshop 教材使用。

---

## 2. 项目结构

```
/root/keith-space/2026-project/longqi-cloudfront/
├── terraform/
│   ├── main.tf                    # Provider（dual region）、模块编排
│   ├── variables.tf               # 所有变量 + enable_* feature flags
│   ├── outputs.tf
│   ├── terraform.tfvars.example
│   ├── modules/
│   │   ├── network/               # SG（ALB/EC2/DB 安全组）
│   │   ├── s3/                    # S3 静态桶 + OAC 策略 + 错误页面
│   │   ├── ec2/                   # EC2 实例 + user_data 部署 Express
│   │   ├── alb/                   # Internal ALB + Target Group + Listener
│   │   ├── cloudfront/            # Distribution + Behaviors + Functions + Error Pages
│   │   ├── cloudfront-cd/         # Continuous Deployment（Staging 分发 + 流量策略）
│   │   ├── waf/                   # WAF Web ACL + Bot Control (us-east-1)
│   │   ├── cognito/               # User Pool + App Client
│   │   ├── database/              # Aurora Serverless v2 + DynamoDB
│   │   └── tag-invalidation/      # Tag-Based Invalidation（Lambda@Edge + DynamoDB + SNS/SQS + Step Functions）
│   └── functions/
│       ├── cf-url-rewrite.js      # CloudFront Function: URL 重写
│       ├── cf-ab-test.js          # CloudFront Function: A/B 测试
│       ├── cf-geo-redirect.js     # CloudFront Function: 地理位置重定向
│       └── edge-tag-extractor.js  # Lambda@Edge: Origin Response 标签提取
├── app/
│   ├── package.json
│   ├── server.js                  # Express 主入口
│   ├── routes/
│   │   ├── products.js            # /api/products — 商品列表（可缓存）
│   │   ├── cart.js                # /api/cart — 购物车（不可缓存）
│   │   ├── user.js                # /api/user — 登录/注册 + UUID 绑定
│   │   ├── orders.js              # /api/orders — 订单（需认证）
│   │   ├── health.js              # /api/health — 健康检查
│   │   ├── debug.js               # /api/debug — 返回所有 request headers
│   │   ├── delay.js               # /api/delay/:ms — 模拟延迟
│   │   └── admin.js               # /api/admin/invalidate-tag — 按标签失效缓存
│   ├── middleware/
│   │   ├── uuid-tracker.js        # UUID cookie 中间件
│   │   └── cognito-auth.js        # Cognito JWT 验证
│   ├── views/                     # EJS 模板
│   │   ├── index.ejs              # 首页
│   │   ├── products.ejs           # 商品列表页
│   │   ├── product-detail.ejs     # 商品详情页
│   │   ├── cart.ejs               # 购物车页
│   │   ├── login.ejs              # 登录/注册页
│   │   └── debug.ejs              # 调试页（显示 headers）
│   └── public/
│       ├── css/style.css
│       └── js/main.js
├── static/                        # 上传到 S3 的静态资源
│   ├── images/
│   ├── fonts/
│   └── assets/
├── scripts/
│   ├── deploy-app.sh              # Express 应用部署脚本
│   └── deploy-static.sh           # S3 静态资源上传脚本
├── hands-on/
│   ├── 01-cloudfront-distribution-multi-origin.md
│   ├── 02-cloudfront-cache-policies.md
│   ├── 03-cloudfront-functions.md
│   ├── 04-cloudfront-waf-basic.md
│   ├── 05-cloudfront-waf-bot-control.md
│   ├── 06-cloudfront-signed-url.md
│   ├── 07-cloudfront-geo-restriction.md
│   ├── 08-cloudfront-error-pages.md
│   ├── 09-cloudfront-oac-s3.md
│   ├── 10-cloudfront-vpc-origin.md
│   ├── 11-cloudfront-continuous-deployment.md
│   └── 12-cloudfront-tag-based-invalidation.md
└── docs/
    └── superpowers/specs/
```

---

## 3. 网络架构

### 3.1 架构总览

本平台采用 **CloudFront → VPC Origin → Internal ALB → EC2** 的全内网架构。这是 AWS 推荐的最佳实践——ALB 不暴露任何公网端口，所有流量必须经过 CloudFront 进入，从根本上消除了绕过 CDN 直接攻击源站的风险。

CloudFront VPC Origin 是 2024 年发布的新功能，它在客户的 VPC 内创建 Elastic Network Interface (ENI)，通过 AWS 内部网络直接连接 Internal ALB，无需 NAT Gateway 或公网 IP。这使得源站可以完全部署在 Private Subnet 中，显著提升了安全性。

```
                          ┌─────────────────────────────────────────┐
                          │            CloudFront Distribution       │
                          │         unice.keithyu.cloud              │
                          │                                         │
                          │  Behaviors:                             │
                          │  /static/* /images/* → S3 Origin (OAC)  │
                          │  /api/*              → ALB Origin (VPC) │
                          │  Default (*)         → ALB Origin (VPC) │
                          │                                         │
                          │  + CF Functions (URL重写/A-B/Geo)       │
                          │  + WAF Web ACL + Bot Control            │
                          │  + Signed URL/Cookie (/premium/*)       │
                          │  + Geo Restriction                      │
                          │  + Custom Error Pages (S3)              │
                          │  + Continuous Deployment (Staging)      │
                          └──────────┬──────────────┬───────────────┘
                                     │              │
                          ┌──────────▼──┐    ┌──────▼──────────┐
                          │  S3 Bucket   │    │  VPC Origin     │
                          │  (OAC 访问)  │    │  (CF → VPC ENI) │
                          │  静态资源     │    └───────┬─────────┘
                          └─────────────┘            │
                                              ┌──────▼──────────┐
                                              │  Internal ALB    │
                                              │  (Private Subnet)│
                                              │  SG: VPC Origin  │
                                              └───────┬──────────┘
                                                      │
                                              ┌───────▼──────────┐
                                              │  EC2 (Express)    │
                                              │  (Private Subnet) │
                                              │  SG: 仅 ALB       │
                                              └──┬─────┬─────┬───┘
                                                 │     │     │
                                    ┌────────────▼┐ ┌──▼───┐ ┌▼────────────┐
                                    │ DynamoDB     │ │Aurora│ │ Cognito     │
                                    │ UUID映射表   │ │Svls  │ │ User Pool   │
                                    └─────────────┘ │v2 PG │ └─────────────┘
                                                    └──────┘
```

### 3.2 安全组规则

安全组采用最小权限原则，每一层只允许来自上一层的流量，形成严格的链式信任关系：

| 组件 | 部署位置 | 入站规则 | 设计意图 |
|------|---------|----------|---------|
| Internal ALB | Private Subnet | 仅 VPC Origin 安全组（HTTP 80） | ALB 完全内网化，只接受 CloudFront 通过 VPC Origin ENI 发来的流量 |
| EC2 | Private Subnet | 仅 ALB 安全组（HTTP 3000） | EC2 只响应 ALB 转发的请求，Express 监听在 3000 端口 |
| Aurora Serverless v2 | Private Subnet | 仅 EC2 安全组（PostgreSQL 5432） | 数据库只接受应用层连接 |
| DynamoDB | AWS 托管 | VPC Endpoint（Gateway 类型） | 通过 VPC Endpoint 访问 DynamoDB，流量不出 VPC |
| S3 | AWS 托管 | OAC 策略限制仅 CloudFront 分发访问；VPC Endpoint（Gateway）供 EC2 上传/读取 | 双通道访问：CloudFront 通过 OAC 分发静态内容，EC2 通过 VPC Endpoint 管理资源 |

### 3.3 外网访问

EC2 部署在 Private Subnet 中，需要通过 NAT Gateway 访问外部网络（用于 `npm install` 安装依赖、调用 Cognito API 等）。本项目假设现有 VPC 已配置 NAT Gateway，Terraform 通过 data source 引用现有路由表，不额外创建 NAT 资源。

如果目标 VPC 没有 NAT Gateway，有两种替代方案：
1. 在 Terraform 中新建 NAT Gateway（增加约 $32/月成本）
2. 为所有 AWS 服务调用配置 VPC Endpoint（DynamoDB Gateway、Cognito Interface、STS Interface 等）

---

## 4. CloudFront Behaviors 与缓存策略

### 4.1 多源多策略设计理念

CloudFront 的 Cache Behavior 是其核心配置机制——通过 URL 路径模式 (Path Pattern) 将不同类型的请求路由到不同的 Origin，并为每种请求类型配置独立的缓存策略、转发规则和功能关联。

本平台设计了 **10 条 Cache Behavior**，覆盖了电商网站的典型场景：

- **静态资源**（CSS/JS/图片）走 S3，长时间缓存，最大化 CDN 命中率
- **可缓存 API**（商品列表）走 ALB，中等缓存，按 Query String 区分不同页面
- **个性化 API**（购物车、用户信息）走 ALB，完全禁用缓存，转发所有 Cookie/Header
- **受保护内容**（会员资源）走 S3，需签名 URL 才能访问
- **调试端点** 完全透传，用于验证 CloudFront 注入的 Header

### 4.2 Behavior 配置详表

| Path Pattern | Origin | Cache Policy | Cookie 转发 | Query String | Header 转发 | 说明 |
|---|---|---|---|---|---|---|
| `/static/*` | S3 (OAC) | CachingOptimized (86400s) | 无 | 无 | 无 | CSS/JS/字体，24 小时缓存 |
| `/images/*` | S3 (OAC) | CachingOptimized (86400s) | 无 | 无 | 无 | 商品图片，24 小时缓存 |
| `/api/products*` | ALB (VPC) | 自定义 ProductCache (3600s) | 无 | 全部转发 | `Accept`, `Accept-Language` | 商品列表可缓存，按 query string（page/category/sort）作为缓存键 |
| `/api/cart*` | ALB (VPC) | CachingDisabled | 全部转发 | 全部转发 | 全部转发 | 购物车强依赖用户身份 cookie，必须禁用缓存 |
| `/api/user*` | ALB (VPC) | CachingDisabled | 全部转发 | 全部转发 | 全部转发 | 登录/注册/UUID 绑定，涉及 Set-Cookie 操作 |
| `/api/orders*` | ALB (VPC) | CachingDisabled | 全部转发 | 全部转发 | 全部转发 | 订单数据高度个性化 |
| `/api/debug*` | ALB (VPC) | CachingDisabled | 全部转发 | 全部转发 | 全部转发 | 调试端点，完全透传以便观察 CloudFront 注入的所有 Header |
| `/api/delay/*` | ALB (VPC) | CachingDisabled | 无 | 无 | 无 | 延迟模拟，用于测试 CloudFront 超时和重试行为 |
| `/premium/*` | S3 (OAC) | CachingOptimized | 无 | 无 | 无 | 签名 URL/Cookie 保护的会员内容 |
| `Default (*)` | ALB (VPC) | 自定义 PageCache (60s) | `x-trace-id`, `aws-waf-token` | 全部转发 | `Host`, `Accept` | SSR 页面，短时缓存（60s）兼顾性能和内容新鲜度 |

### 4.3 为什么选择这样的缓存策略

- **CachingOptimized**：AWS 托管策略，TTL 为 24 小时，适合不频繁更新的静态资源。启用 Gzip/Brotli 压缩，最大化传输效率。
- **CachingDisabled**：AWS 托管策略，CloudFront 不缓存任何内容，但仍提供全球加速和安全防护（WAF、DDoS Protection）。适合个性化 API。
- **自定义 ProductCache (3600s)**：商品数据更新频率适中（通常小时级别），1 小时缓存是性能和新鲜度的平衡点。通过转发 Query String 确保不同页码/筛选条件有独立缓存。
- **自定义 PageCache (60s)**：SSR 页面需要较高新鲜度，60 秒短缓存可以在高并发时分担源站压力，同时保证内容近实时更新。仅转发 `x-trace-id` 和 `aws-waf-token` 两个 cookie，避免不必要的 cookie 破坏缓存命中率。

---

## 5. CloudFront Functions

### 5.1 边缘计算概述

CloudFront Functions 是运行在 CloudFront 边缘节点上的轻量级 JavaScript 函数，执行延迟低于 1ms，适合请求/响应的简单变换。与 Lambda@Edge 相比，Functions 的优势是更低延迟、更低成本（每百万次调用 $0.10），但限制更多（最大 10KB 代码、2ms 执行时间、不能访问网络/文件系统）。

本平台使用 3 个 CloudFront Functions 演示常见的边缘处理场景：

### 5.2 Function 配置

| Function | 触发阶段 | 绑定 Behavior | 逻辑说明 |
|---|---|---|---|
| `cf-url-rewrite` | Viewer Request | Default (*) | **友好 URL 重写**：将用户可读的 URL（如 `/products/123`）重写为应用内部路由（`/api/products/123`）。这使得 CloudFront 的 Behavior 匹配和实际的应用路由可以解耦。 |
| `cf-ab-test` | Viewer Request | Default (*) | **A/B 测试分流**：检查请求中的 `x-ab-group` cookie。若存在，直接使用；若不存在，随机分配 A 或 B 组，通过 Set-Cookie 持久化，并在请求头中添加 `X-AB-Group` 供源站使用。这是无需服务端改动即可实现 A/B 测试的典型模式。 |
| `cf-geo-redirect` | Viewer Request | Default (*) | **地理位置重定向**：利用 CloudFront 自动注入的 `CloudFront-Viewer-Country` header 判断访问者所在国家。中国大陆（CN）用户自动重定向到 `/cn/` 前缀路径，实现多区域内容分发。 |

### 5.3 为什么不用 Lambda@Edge

本项目的三个函数都是纯请求变换（URL 改写、cookie 读写、重定向），不涉及网络调用或复杂计算，CloudFront Functions 完全满足需求且成本更低。如果未来需要更复杂的边缘逻辑（如查询数据库做动态路由），可以升级为 Lambda@Edge。

---

## 6. WAF 安全防护

### 6.1 AWS WAF 概述

AWS WAF (Web Application Firewall) 是一种 Web 应用防火墙，可以保护 CloudFront 分发免受常见 Web 攻击。WAF 的 Web ACL 必须部署在 **us-east-1** 区域才能与 CloudFront 关联（这是 CloudFront 的全球服务特性决定的）。

本平台的 WAF 配置分为两层：**基础防护**（默认开启）和 **Bot Control**（通过 feature flag 按需开启，因为有额外费用）。

### 6.2 WAF 规则配置

| 规则 | 优先级 | 动作 | 说明 |
|---|---|---|---|
| AWS Common Rule Set | 1 | Count/Block | AWS 托管规则，覆盖 OWASP Top 10 常见攻击（SQL 注入、XSS、SSRF 等）。建议初始设为 Count 模式观察，确认无误报后切换为 Block。 |
| AWS Known Bad Inputs | 2 | Block | 检测已知的恶意输入模式，如 Log4j 漏洞利用 payload、恶意 User-Agent 等。 |
| AWS Bot Control | 3 | Challenge/Block | 机器人检测与管控（见下方详细说明）。通过 `enable_waf_bot_control` feature flag 控制。 |
| Rate Limit (自定义) | 4 | Block | 速率限制：同一 IP 在 5 分钟内超过 2000 次请求将被封禁。防止暴力破解和简单的 DDoS 攻击。 |
| IP Reputation | 5 | Count | AWS 维护的恶意 IP 信誉库，标记已知的恶意 IP 地址（如僵尸网络节点、匿名代理）。设为 Count 用于监控。 |
| Geo Block (自定义) | 6 | Block | 配合地理限制功能，可以封禁来自特定国家的请求。规则中指定国家代码列表。 |

### 6.3 Bot Control + JS SDK 集成

AWS WAF Bot Control 提供两个级别的机器人检测：

- **Common 级别**：基于 HTTP 指纹（User-Agent、Header 顺序等）识别已知机器人。包含对 SEO 爬虫（Googlebot）、社交媒体爬虫等的分类。
- **Targeted 级别**（本平台选用）：在 Common 基础上增加行为分析和 ML 模型，能检测高级爬虫和自动化工具。费用为 $10/月基础费 + $1/百万请求。

**JS SDK 集成**是 Bot Control 的关键组成部分。它通过在浏览器端运行 JavaScript 代码，收集浏览器环境信息（Canvas 指纹、WebGL 渲染、JS 引擎特征等）并生成一个加密的 `aws-waf-token` cookie。WAF 在收到请求时验证这个 token，以此区分真实浏览器和无头脚本/自动化工具。

**前端集成方式**：在所有 EJS 模板的 `<head>` 标签内引入 WAF JS SDK：

```html
<script type="text/javascript" src="/challenge.js" defer></script>
```

> 注：`/challenge.js` 的实际 URL 由 WAF 自动生成，格式为 `https://<distribution-domain>/<token-domain>/challenge.js`。

**工作流程**：

1. 用户首次访问页面，浏览器加载并执行 WAF JS SDK
2. SDK 静默运行浏览器环境检测（Canvas/WebGL/JS 引擎指纹等），耗时约 200-500ms
3. 检测完成后生成 `aws-waf-token` cookie，有效期 5 分钟（自动续期）
4. 后续所有请求自动携带该 cookie
5. CloudFront 将请求转发给 WAF，WAF 验证 token：
   - Token 有效 → 放行
   - Token 缺失/无效 → 返回 Challenge 页面（对用户透明的静默验证）
   - Challenge 反复失败 → Block（判定为机器人）

**对 CloudFront Cache Behavior 的影响**：所有需要 Bot Control 保护的 Behavior 必须在 cookie 转发列表中包含 `aws-waf-token`。本平台的 `Default (*)` Behavior 已包含此 cookie。

---

## 7. 签名 URL/Cookie

### 7.1 功能说明

CloudFront 签名 URL 和签名 Cookie 用于限制对私有内容的访问。典型应用场景包括：付费内容（视频课程、电子书）、会员专属资源、限时下载链接等。

签名机制基于 RSA 非对称加密：

1. **Terraform 生成 RSA 密钥对**（2048 位），私钥存储在 EC2 实例上，公钥注册到 CloudFront 作为 Trusted Key Group
2. **EC2 应用签发签名 URL**：当登录用户请求 `/api/user/signed-url` 时，应用使用私钥对 URL 进行签名，附加过期时间、允许的 IP 范围等策略
3. **CloudFront 验证签名**：用户使用签名 URL 访问 `/premium/*` 路径时，CloudFront 用注册的公钥验证签名，有效则放行，无效或过期则返回 403

### 7.2 本平台实现

- **保护路径**：`/premium/*`（S3 上的模拟会员内容）
- **签名端点**：`/api/user/signed-url`（需 JWT 认证）
- **签名策略**：URL 有效期 1 小时，不限制 IP
- **演示场景**：用户登录后点击"获取会员内容"按钮，前端调用签名端点获取签名 URL，然后重定向到该 URL 下载/查看内容

---

## 8. 自定义错误页面

### 8.1 功能说明

当 CloudFront 从源站收到错误响应（4xx/5xx），默认会将原始错误直接返回给用户，体验不佳。通过配置自定义错误页面，可以将这些错误替换为品牌化的友好页面，同时 CloudFront 会缓存错误响应一段时间，减少对源站的重复请求。

### 8.2 错误页面配置

| HTTP Status | 触发场景 | S3 路径 | 缓存 TTL | 返回的 HTTP 状态码 |
|---|---|---|---|---|
| 403 Forbidden | 签名 URL 过期/无效、OAC 拒绝、WAF 拦截 | `/static/errors/403.html` | 300s | 403 |
| 404 Not Found | 请求的资源不存在 | `/static/errors/404.html` | 300s | 404 |
| 500 Internal Server Error | EC2 应用异常 | `/static/errors/500.html` | 60s | 500 |
| 502 Bad Gateway | ALB 无法连接 EC2 | `/static/errors/502.html` | 60s | 502 |

> 注：5xx 错误的缓存 TTL 设置较短（60s），因为这类错误通常是暂时性的，源站恢复后应尽快返回正常内容。

---

## 9. CloudFront Continuous Deployment（持续部署）

### 9.1 功能概述

CloudFront Continuous Deployment 是 CloudFront 的灰度发布功能，允许你在不影响生产流量的情况下测试配置变更。它通过创建一个 **Staging Distribution**（暂存分发），将一部分真实流量（基于权重或特定 Header）路由到 Staging 环境进行验证，确认无误后再将变更提升 (Promote) 到生产 Distribution。

这个功能解决了 CloudFront 配置变更的核心痛点：
- **传统方式**：直接修改生产 Distribution → 配置全球传播需要数分钟 → 如果出错，回滚同样需要数分钟 → 期间所有用户受影响
- **Continuous Deployment**：变更先部署到 Staging → 只有小比例流量受影响 → 验证通过后一键提升 → 回滚只需取消 Staging 即刻生效

### 9.2 本平台实现

**Terraform 模块 (`cloudfront-cd/`)**：

```
aws_cloudfront_continuous_deployment_policy
├── staging_distribution_dns_names    # Staging 分发的域名
├── traffic_config
│   ├── type: "SingleWeight"          # 基于权重的流量分配
│   ├── single_weight_config
│   │   └── weight: 0.05             # 5% 流量导入 Staging
│   └── (可选) type: "SingleHeader"   # 或基于特定 Header 分流
│       └── header_name: "aws-cf-cd-staging"
│       └── header_value: "true"
└── enabled: var.enable_continuous_deployment

aws_cloudfront_distribution (staging)
├── staging: true                     # 标记为 Staging 分发
├── continuous_deployment_policy_id   # 关联策略
└── (配置与 Production 相同，用于验证变更)
```

**使用流程**：

1. **创建 Staging Distribution**：Terraform apply 时自动创建，继承 Production 的全部配置
2. **修改 Staging 配置**：在 Staging 上测试新的 Cache Behavior、Function、WAF 规则等
3. **灰度验证**：通过权重分流（5% 真实流量）或 Header 分流（测试人员手动添加 Header）验证
4. **监控指标**：对比 Production 和 Staging 的错误率、延迟、缓存命中率
5. **提升到生产**：验证通过后，调用 `aws cloudfront update-distribution --id <prod-id> --if-match <etag>` 将 Staging 配置提升为 Production
6. **回滚**：如果发现问题，直接禁用 Staging Distribution，所有流量立即回到 Production

### 9.3 典型演示场景

- **场景 A：缓存策略变更**：将 `/api/products*` 的缓存 TTL 从 3600s 改为 7200s，通过 Staging 验证命中率变化后再上线
- **场景 B：新增 CloudFront Function**：在 Staging 上绑定新的 URL 重写规则，用 Header 分流让测试人员验证重写逻辑
- **场景 C：WAF 规则调整**：将 Common Rule Set 从 Count 切换为 Block，先在 5% 流量上观察是否有误报

### 9.4 Feature Flag

| 变量 | 默认值 | 说明 |
|---|---|---|
| `enable_continuous_deployment` | `false` | 默认关闭，需要演示 CI/CD 时开启。Staging Distribution 会产生额外费用（与 Production 相同的请求计费）。 |

---

## 10. CloudFront Tag-Based Invalidation（基于标签的精准缓存失效）

### 10.1 功能概述

传统的 CloudFront 缓存失效 (Invalidation) 基于 **URL 路径通配符**——例如 `/api/products*` 会失效所有商品 API 的缓存。这种方式存在明显局限：

- **粒度过粗**：当某一个商品（如 product-123）的价格更新时，`/api/products*` 会失效所有商品的缓存，包括未变更的商品，导致源站承受不必要的回源压力
- **跨路径关联困难**：同一商品可能出现在多条路径上（`/api/products/123`、`/products?category=wigs`、`/` 首页推荐），路径通配符无法精准覆盖所有关联缓存
- **运维成本高**：随着路径结构复杂化，维护失效规则的成本线性增长

**Tag-Based Invalidation（基于标签的缓存失效）** 解决了这个问题。核心思想是：在源站响应中附加 **内容标签**（如 `Cache-Tag: product-123, category-wigs`），由 Lambda@Edge 在边缘提取标签并存入 DynamoDB 映射表。当商品信息更新时，只需指定标签名称，系统自动查询该标签关联的所有 URL 并精准失效，无需手动维护路径列表。

在电商场景中，这意味着：当 product-123 的价格从 $99 更新为 $79 时，系统仅失效携带 `product-123` 标签的缓存对象（可能包括商品详情页、列表页、首页推荐等多条路径），而不会影响其他商品的缓存。

### 10.2 架构说明

本功能的架构基于 [AWS 官方博客](https://aws.amazon.com/cn/blogs/networking-and-content-delivery/tag-based-invalidation-in-amazon-cloudfront/) 和 [GitHub 示例代码](https://github.com/aws-samples/amazon-cloudfront-tagbased-invalidations) 的参考实现，包含两条工作流：**标签采集流（Ingestion）** 和 **标签失效流（Purge）**。

#### 10.2.1 标签采集流（Ingestion Workflow）

```
CloudFront Cache Miss
  │
  ├─ Origin 返回响应，携带 Cache-Tag header
  │   例: Cache-Tag: product-123, category-wigs
  │
  ├─ Lambda@Edge (Origin Response) 拦截响应
  │   ├─ 解析 Cache-Tag header，提取标签列表
  │   ├─ 发布消息到 SNS Topic（当前区域）
  │   │   payload: { url, tags[], ttl }
  │   └─ 从响应中移除 Cache-Tag header（不暴露给客户端）
  │
  ├─ SNS → SQS（跨区域聚合）
  │   Lambda@Edge 在全球多个 Regional Edge Cache 执行，
  │   每个区域的 SNS Topic 将消息汇聚到中央 SQS 队列
  │
  └─ EventBridge Scheduler（每 2 分钟触发）
      └─ Lambda (Ingest Processor)
          └─ 从 SQS 批量读取消息，写入 DynamoDB 映射表
```

#### 10.2.2 标签失效流（Purge Workflow）

```
管理员调用 POST /api/admin/invalidate-tag
  │   body: { "tags": ["product-123"] }
  │
  ├─ Express 路由触发 Step Functions 执行
  │   input: { distributionId, tags }
  │
  ├─ Step Functions 工作流
  │   ├─ Step 1: 查询 DynamoDB，获取标签关联的所有 URL
  │   │   例: product-123 → ["/api/products/123", "/products?category=wigs&page=1", "/"]
  │   │
  │   ├─ Step 2: URL 去重 + 批量分组
  │   │   CloudFront 每次 Invalidation 最多 3000 个路径，
  │   │   多个标签可能关联相同 URL，需去重后分批
  │   │
  │   ├─ Step 3: 提交到失效队列（SQS）
  │   │
  │   └─ Step 4: 速率控制 Lambda
  │       ├─ 检查当前活跃的 Invalidation 数量（CloudFront 限制：同时 3000 个）
  │       ├─ 在配额允许范围内调用 CloudFront CreateInvalidation API
  │       └─ 未提交的 URL 等待下次调度
  │
  └─ 完成：Step Functions 执行状态变为 Succeeded
      CloudFront Console 可查看 Invalidation 详情和状态
```

#### 10.2.3 核心组件

| 组件 | 部署区域 | 功能 |
|------|---------|------|
| **Lambda@Edge (Origin Response)** | us-east-1（自动复制到边缘） | 拦截源站响应，提取 `Cache-Tag` header 中的标签，发布到 SNS，移除 header 后返回给 CloudFront 缓存 |
| **SNS Topics** | 各 Regional Edge Cache 区域 | 接收 Lambda@Edge 发布的标签消息，转发到中央 SQS |
| **SQS Queue** | 主区域 (ap-northeast-1) | 聚合来自全球各区域的标签消息 |
| **DynamoDB 表: `unice-cache-tags`** | 主区域 (ap-northeast-1) | 存储 tag → URL 映射关系（PK=tag, SK=url），支持 TTL 自动过期 |
| **EventBridge Scheduler** | 主区域 | 每 2 分钟触发 Ingest Lambda 和 Purge Lambda |
| **Lambda (Ingest Processor)** | 主区域 | 从 SQS 批量读取消息，写入 DynamoDB |
| **Step Functions** | 主区域 | 编排失效流程：查询 DynamoDB → 去重分组 → 速率控制 → 调用 CloudFront Invalidation API |
| **Lambda (Purge Executor)** | 主区域 | Step Functions 中的执行节点，负责实际调用 CloudFront CreateInvalidation API |

### 10.3 本平台实现

#### 10.3.1 Express 端：添加 Cache-Tag Header

商品相关的 API 响应会自动添加 `Cache-Tag` header，标签包含商品 ID 和分类信息：

```javascript
// routes/products.js — 商品详情
app.get('/api/products/:id', (req, res) => {
  const product = getProduct(req.params.id);
  // 添加 Cache-Tag header，Lambda@Edge 将在边缘提取
  res.set('Cache-Tag', `product-${product.id}, category-${product.category}`);
  res.json(product);
});

// routes/products.js — 商品列表
app.get('/api/products', (req, res) => {
  const products = getProducts(req.query);
  // 列表页标签包含所有出现的商品 ID 和分类
  const tags = products.flatMap(p => [`product-${p.id}`, `category-${p.category}`]);
  res.set('Cache-Tag', [...new Set(tags)].join(', '));
  res.json(products);
});
```

#### 10.3.2 管理端点：按标签触发失效

新增 `/api/admin/invalidate-tag` 端点，接收标签列表并触发 Step Functions 执行：

```javascript
// routes/admin.js
app.post('/api/admin/invalidate-tag', cognitoAuth, async (req, res) => {
  const { tags } = req.body; // 例: ["product-123", "category-wigs"]
  const execution = await stepFunctions.startExecution({
    stateMachineArn: process.env.TAG_PURGE_STATE_MACHINE_ARN,
    input: JSON.stringify({
      distributionId: process.env.CLOUDFRONT_DISTRIBUTION_ID,
      tags: tags
    })
  }).promise();
  res.json({ executionArn: execution.executionArn, status: 'RUNNING' });
});
```

#### 10.3.3 DynamoDB 新表: `unice-cache-tags`

| 属性 | 类型 | 角色 | 说明 |
|------|------|------|------|
| `tag` | String | **PK** | 缓存标签名（如 `product-123`、`category-wigs`） |
| `url` | String | **SK** | 被标记的 URL 路径（如 `/api/products/123`） |
| `distribution_id` | String | - | CloudFront Distribution ID |
| `created_at` | String | - | 映射创建时间，ISO 8601 格式 |
| `ttl` | Number | **TTL** | Unix 时间戳，自动过期。默认跟随 Cache-Control max-age，防止映射表无限膨胀 |

- **计费模式**: PAY_PER_REQUEST（按需计费，与 UUID 映射表保持一致）
- **TTL**: 启用。当缓存对象自然过期后，映射记录也应清理，避免数据膨胀。TTL 值来源于响应的 `Cache-Control` max-age 或自定义 `tag-ttl` header

#### 10.3.4 Lambda@Edge Origin Response 函数

```javascript
// functions/edge-tag-extractor.js
exports.handler = async (event) => {
  const response = event.Records[0].cf.response;
  const request = event.Records[0].cf.request;
  const tagHeader = response.headers['cache-tag'];

  if (tagHeader) {
    const tags = tagHeader[0].value.split(',').map(t => t.trim());
    const url = request.uri + (request.querystring ? '?' + request.querystring : '');

    // 发布到 SNS（当前区域）
    await sns.publish({
      TopicArn: process.env.SNS_TOPIC_ARN,
      Message: JSON.stringify({ url, tags, distributionId: process.env.DISTRIBUTION_ID })
    }).promise();

    // 移除 Cache-Tag header，不暴露给客户端
    delete response.headers['cache-tag'];
  }

  return response;
};
```

### 10.4 参考代码

本功能的基础架构参考 AWS 官方示例仓库 [amazon-cloudfront-tagbased-invalidations](https://github.com/aws-samples/amazon-cloudfront-tagbased-invalidations)（MIT-0 许可证）。该仓库使用 AWS CDK 部署，本项目将其适配为 Terraform 模块，主要调整包括：

- **CDK → Terraform**：将 CDK Stack 转换为 Terraform `tag-invalidation/` 模块
- **表名和标签规范**：DynamoDB 表名改为 `unice-cache-tags`，标签 header 改为 `Cache-Tag`（与业界惯例一致）
- **触发方式**：原方案直接通过 Step Functions Console 触发；本项目新增 Express API 端点 `/api/admin/invalidate-tag` 作为触发入口，更贴合实际应用场景
- **区域精简**：原方案部署到 11 个 Regional Edge Cache 区域；本项目仅部署主区域 (ap-northeast-1) 和 us-east-1（Lambda@Edge 要求），降低演示环境复杂度

### 10.5 对现有设计的影响

| 影响范围 | 变更内容 |
|---------|---------|
| **Terraform 模块** | 新增 `modules/tag-invalidation/`：Lambda@Edge 函数 + DynamoDB `unice-cache-tags` 表 + IAM Role（Lambda 执行角色、CloudFront Invalidation 权限）+ SNS/SQS + Step Functions 状态机 + EventBridge Scheduler |
| **Express 路由** | 新增 `routes/admin.js`：`POST /api/admin/invalidate-tag` 端点 |
| **Express 商品路由** | 修改 `routes/products.js`：在商品响应中添加 `Cache-Tag` header |
| **CloudFront Behavior** | `/api/products*` Behavior 的 Origin Response 事件绑定 Lambda@Edge 函数 `edge-tag-extractor` |
| **Feature Flag** | 新增 `enable_tag_invalidation`（默认 `false`），控制整个 tag-invalidation 模块的创建 |
| **Hands-on 文档** | 新增第 12 篇 `cloudfront-tag-based-invalidation.md` |
| **安全组** | 无变更——Lambda@Edge 和 Step Functions 均为 AWS 托管服务，不涉及 VPC 安全组 |

### 10.6 Feature Flag

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `enable_tag_invalidation` | `false` | 默认关闭。开启后部署 Lambda@Edge、DynamoDB 表、SNS/SQS、Step Functions 等资源。关闭时商品响应不添加 `Cache-Tag` header，`/api/admin/invalidate-tag` 端点返回 404。 |

> **费用估算**（基于 AWS 示例仓库的月度模型，按 100M CloudFront 请求 + 1000 次标签失效计算）：Lambda@Edge ~$27 + DynamoDB ~$75 + CloudFront Invalidation ~$95 + SQS ~$8 + SNS ~$0.3 = **总计约 $205/月**。演示环境实际流量远低于此，预计月费用 < $5。

---

## 11. UUID 追踪系统

### 11.1 设计理念

在电商场景中，用户行为追踪是个性化推荐、转化分析和性能诊断的基础。传统方案（如 Google Analytics 的 `_ga` cookie）由前端 JavaScript 生成，容易被广告拦截器屏蔽。

本平台采用 **服务端 UUID 方案**：由 EC2 应用服务器在中间件层为每个用户分配唯一的 UUID（`x-trace-id`），存储在 HttpOnly cookie 中（前端 JavaScript 无法读取，也不会被广告拦截器拦截）。CloudFront 仅做透传，不参与 UUID 的生成或管理。

当用户注册/登录后，UUID 会绑定到其 Cognito 账号，实现 **跨设备统一追踪**——用户在手机上登录后会获得和 PC 端相同的 UUID。

### 11.2 中间件流程 (uuid-tracker.js)

```
请求进入 Express
  │
  ├─ 读取 cookie: x-trace-id
  │
  ├─ 有 cookie?
  │   ├─ 是 → req.traceId = cookie 值，继续处理
  │   └─ 否 → 生成 UUID v4
  │           ├─ Set-Cookie: x-trace-id=<UUID>; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=63072000
  │           └─ req.traceId = 新 UUID，req.isNewUser = true
  │
  └─ 所有响应 header 添加 X-Trace-Id: <UUID>（方便调试时通过浏览器 DevTools 或 curl 查看）
```

> Cookie 有效期为 **2 年**（63072000 秒），覆盖绝大多数用户的回访周期。

### 11.3 登录时 UUID 绑定

```
POST /api/user/login
  │
  ├─ 1. Cognito 验证用户名/密码 → 获取 JWT (access_token + id_token)
  │
  ├─ 2. 查询 DynamoDB: unice-trace-mapping
  │     PK = cognito_user_id
  │
  ├─ 3. 记录存在?
  │     ├─ 是 → 用数据库中的 UUID 覆盖当前 cookie（跨设备统一）
  │     │       Set-Cookie: x-trace-id=<数据库中的UUID>
  │     │       更新 last_device 和 last_seen
  │     └─ 否 → 将当前 req.traceId 写入 DynamoDB 绑定
  │             { cognito_user_id, trace_id, created_at, last_device, last_seen }
  │
  └─ 4. 返回 JWT token + 用户信息 + trace_id
```

### 11.4 DynamoDB 表: `unice-trace-mapping`

| 属性 | 类型 | 角色 | 说明 |
|---|---|---|---|
| `cognito_user_id` | String | **PK** | Cognito 用户唯一标识符 (sub) |
| `trace_id` | String | **GSI-PK** | UUID v4，用于链路追踪 |
| `created_at` | String | - | 首次绑定时间，ISO 8601 格式 |
| `last_device` | String | - | 最近登录设备的 User-Agent 摘要 |
| `last_seen` | String | - | 最近活跃时间，ISO 8601 格式 |

- **GSI: `trace_id-index`**：通过 UUID 反查用户账号，用于日志分析和调试
- **计费模式**: PAY_PER_REQUEST（按需计费，测试环境流量低，比预置容量更经济）
- **TTL**: 无（账号绑定记录永久保留，不设过期时间）

### 11.5 匿名用户 vs 登录用户

| 维度 | 匿名用户 | 登录用户 |
|---|---|---|
| UUID 来源 | Express 中间件生成 | DynamoDB 中绑定的 UUID |
| 持久性 | 仅 cookie（2 年有效，清 cookie 即丢失） | DynamoDB 永久保留，任何设备登录可恢复 |
| 跨设备 | 不支持（每个设备独立 UUID） | 支持（登录后统一为同一 UUID） |
| 数据存储 | 不写入 DynamoDB | DynamoDB 记录 |

---

## 12. Express 应用 API 路由

### 12.1 路由设计说明

Express 应用提供两类路由：**页面路由**（SSR 渲染 EJS 模板）和 **API 路由**（返回 JSON）。这种分离设计使得 CloudFront 可以为两类路由配置不同的缓存策略——页面路由使用短 TTL 缓存，API 路由根据数据特性选择缓存或不缓存。

特别设计了 `/api/debug` 和 `/api/delay/:ms` 两个调试端点：
- **debug** 端点返回 Express 收到的所有 HTTP Header，用于验证 CloudFront 是否正确转发/注入了特定 Header（如 `CloudFront-Viewer-Country`、`X-AB-Group` 等）
- **delay** 端点接受一个毫秒参数，模拟慢响应，用于测试 CloudFront 的 Origin Timeout 和 Keep-Alive 行为

### 12.2 路由详表

| 路由 | 方法 | 认证 | 缓存 | 功能 |
|---|---|---|---|---|
| `/` | GET | 无 | 60s | 首页，展示推荐商品 |
| `/products` | GET | 无 | 60s | 商品列表页 (SSR) |
| `/products/:id` | GET | 无 | 60s | 商品详情页 (SSR) |
| `/cart` | GET | 无 | 不缓存 | 购物车页面 |
| `/login` | GET | 无 | 不缓存 | 登录/注册页面 |
| `/api/products` | GET | 无 | 3600s | 商品 JSON，支持 `?page=&category=&sort=` |
| `/api/products/:id` | GET | 无 | 3600s | 单个商品 JSON |
| `/api/cart` | GET/POST/DELETE | JWT | 不缓存 | 购物车 CRUD |
| `/api/user/register` | POST | 无 | 不缓存 | Cognito 注册 + UUID 绑定 |
| `/api/user/login` | POST | 无 | 不缓存 | Cognito 登录 + UUID 跨设备统一 |
| `/api/user/profile` | GET | JWT | 不缓存 | 用户信息 + 当前 trace_id |
| `/api/user/signed-url` | GET | JWT | 不缓存 | 生成 `/premium/*` 的签名 URL |
| `/api/orders` | GET/POST | JWT | 不缓存 | 订单列表/创建 |
| `/api/health` | GET | 无 | 不缓存 | 健康检查：`{ status, timestamp, traceId }` |
| `/api/debug` | GET | 无 | 不缓存 | 返回所有 request headers（调试利器） |
| `/api/delay/:ms` | GET | 无 | 不缓存 | `setTimeout(ms)` 后响应，测试超时行为 |
| `/api/admin/invalidate-tag` | POST | JWT | 不缓存 | 按标签失效缓存：接收 `{ tags: ["product-123"] }`，查询 DynamoDB 映射表获取关联 URL，调用 CloudFront Invalidation API。需 `enable_tag_invalidation` 开启 |
| `/debug` | GET | 无 | 不缓存 | Debug HTML 页面（可视化展示 headers/cookies） |

---

## 13. 数据库

### 13.1 Aurora Serverless v2 PostgreSQL

Aurora Serverless v2 提供按需自动扩缩容的关系型数据库服务，适合流量波动大或使用不频繁的场景。本平台使用 PostgreSQL 引擎存储模拟商品和订单数据。

**配置参数**：
- **ACU 范围**: 0.5 (最小) ~ 2 (最大)，测试环境足够使用
- **安全组**: 仅允许 EC2 安全组入站（PostgreSQL 5432 端口）
- **初始数据**: 通过 seed 脚本预填 20-30 条模拟商品数据

**数据库 Schema**：

```sql
-- 商品表：存储模拟的电商商品数据
CREATE TABLE products (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100),
    price DECIMAL(10,2),
    image_url VARCHAR(500),        -- 指向 S3 的图片 URL
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 订单表：记录用户下单信息
CREATE TABLE orders (
    id SERIAL PRIMARY KEY,
    cognito_user_id VARCHAR(255) NOT NULL,
    trace_id VARCHAR(36),          -- 关联 UUID 追踪
    items_json JSONB,              -- 购买商品列表
    total DECIMAL(10,2),
    status VARCHAR(50) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT NOW()
);
```

### 13.2 DynamoDB

DynamoDB 用于 UUID 追踪系统的账号绑定（详见 Section 11.4）以及 Tag-Based Invalidation 的标签映射（详见 Section 10.3）。

---

## 14. Cognito 用户认证

### 14.1 架构选择

本平台采用 **Cognito + Express 混合认证**模式：

- **Cognito User Pool** 负责用户注册/登录的核心逻辑（密码加密存储、JWT 签发、邮箱验证等）
- **Express 应用** 负责渲染登录页面、调用 Cognito API、管理 Session 和 UUID 绑定
- **CloudFront 完全透传**，不参与认证判断——这是刻意设计的，目的是演示 CloudFront 对动态认证流程的兼容性

### 14.2 配置

- **User Pool**: `unice-user-pool`
- **App Client**: `unice-web-client`（无 client secret，适用于服务端调用）
- **Auth Flow**: `USER_PASSWORD_AUTH`（Express 后端代为调用 Cognito API 认证）
- **JWT 验证**: Express 使用 `aws-jwt-verify` 库验证 Cognito 签发的 JWT
- **无 Hosted UI 依赖**：登录/注册页面由 Express EJS 模板渲染，风格与网站统一

---

## 15. Terraform Feature Flags

Feature Flags 允许按需开启/关闭各功能模块，方便逐步演示和控制成本：

| 变量 | 默认值 | 说明 | 费用影响 |
|---|---|---|---|
| `enable_cloudfront` | `true` | CloudFront 分发 | 按请求量计费 |
| `enable_waf` | `true` | WAF 基础规则（Common/Bad Inputs/Rate Limit/IP Reputation） | $5/月 Web ACL + $1/月/规则 |
| `enable_waf_bot_control` | `false` | Bot Control Targeted + JS SDK | 额外 $10/月 + $1/百万请求 |
| `enable_signed_url` | `true` | 签名 URL/Cookie（Trusted Key Group） | 无额外费用 |
| `enable_geo_restriction` | `true` | 地理限制 | 无额外费用 |
| `enable_cognito` | `true` | Cognito User Pool | 免费层 50,000 MAU |
| `enable_aurora` | `true` | Aurora Serverless v2 | 最低约 $43/月 (0.5 ACU) |
| `enable_continuous_deployment` | `false` | CloudFront Continuous Deployment（Staging 分发） | Staging 分发的请求单独计费 |
| `enable_tag_invalidation` | `false` | Tag-Based Invalidation（Lambda@Edge + DynamoDB 映射 + Step Functions 编排） | Lambda@Edge 按请求计费 + DynamoDB 按需计费 + Step Functions 状态转换计费 |
| `enable_cloudfront_logging` | `false` | CloudFront Standard Logging | S3 存储费用 |
| `enable_response_headers_policy` | `true` | Response Headers Policy（安全响应头） | 无额外费用 |

---

## 16. 已有资源引用

以下资源已在 AWS 账号中存在，Terraform 通过 data source 引用，不额外创建：

| 资源 | 值 | 说明 |
|---|---|---|
| VPC | `vpc-086e15047c7f68e87` | 现有 VPC，位于 ap-northeast-1 |
| ACM 证书 (us-east-1) | `arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2` | 通配符证书 `*.keithyu.cloud`，用于 CloudFront |
| Route53 Hosted Zone | `keithyu.cloud` | 域名托管区，用于创建 `unice.keithyu.cloud` ALIAS 记录 |
| SSH Key Pair | `keith-secret` | EC2 实例 SSH 访问密钥 |
| AWS Profile | `default` | 本地 AWS CLI 配置的默认 profile |
| Region | `ap-northeast-1` | 东京区域，所有资源（除 WAF/ACM）部署于此 |

---

## 17. Hands-on 文档目录

每篇文档面向具备基础 AWS 经验的技术人员，包含 AWS Console 操作步骤、关键配置截图位置说明、验证方法和常见问题排查：

| 编号 | 文件名 | 内容概要 |
|---|---|---|
| 01 | `cloudfront-distribution-multi-origin.md` | 创建 CloudFront Distribution，配置 S3 和 ALB (VPC Origin) 双源，设置多条 Cache Behavior 实现路径路由 |
| 02 | `cloudfront-cache-policies.md` | 创建自定义 Cache Policy 和 Origin Request Policy，理解 Cache Key 的组成（Header/Cookie/Query String），对比不同策略的缓存命中率 |
| 03 | `cloudfront-functions.md` | 编写和部署 CloudFront Functions，实现 URL 重写、A/B 测试分流、地理位置重定向，包含测试和调试方法 |
| 04 | `cloudfront-waf-basic.md` | 创建 WAF Web ACL（us-east-1），添加 AWS 托管规则和自定义速率限制规则，关联到 CloudFront Distribution |
| 05 | `cloudfront-waf-bot-control.md` | 启用 Bot Control Targeted 级别，集成 WAF JS SDK 到前端页面，验证 Bot 检测效果（对比 curl vs 浏览器） |
| 06 | `cloudfront-signed-url.md` | 创建 CloudFront Key Group，生成 RSA 密钥对，配置 Trusted Key Group，实现签名 URL 保护私有内容 |
| 07 | `cloudfront-geo-restriction.md` | 配置 CloudFront 地理限制（白名单/黑名单），配合 WAF Geo Block 规则，验证不同国家的访问行为 |
| 08 | `cloudfront-error-pages.md` | 配置自定义错误页面，上传错误页面到 S3，设置错误缓存 TTL，测试各种错误场景（403/404/500/502） |
| 09 | `cloudfront-oac-s3.md` | 配置 Origin Access Control (OAC) 保护 S3 源，理解 OAC vs OAI 的区别，设置 S3 Bucket Policy |
| 10 | `cloudfront-vpc-origin.md` | 配置 VPC Origin 连接 Internal ALB，理解 VPC Origin 的安全组配置，验证全内网架构的流量路径 |
| 11 | `cloudfront-continuous-deployment.md` | 创建 Staging Distribution 和 Continuous Deployment Policy，配置流量分流策略，演示灰度发布和回滚流程 |
| 12 | `cloudfront-tag-based-invalidation.md` | 实现基于内容标签的精准缓存失效，配置 Lambda@Edge 提取 Cache-Tag、DynamoDB 存储映射、按标签触发 CloudFront Invalidation |

---

## 18. Express 应用部署机制

### 18.1 背景

Terraform 的 `user_data.sh` 脚本仅完成 EC2 实例的 **基础环境准备**：

- 安装 Node.js 20 LTS（通过 NodeSource 仓库）
- 全局安装 pm2 进程管理器
- 部署一个 **占位 Express 应用**，仅包含 `/api/health`、`/api/debug`、`/api/delay/:ms` 三个端点
- 通过 pm2 启动并设置开机自启

这个占位应用的作用是确保 Terraform apply 完成后，ALB Health Check 能立即通过（返回 200），CloudFront → VPC Origin → ALB → EC2 的链路可以验证连通性。

完整的 `app/` 目录代码（包含商品路由、购物车、用户认证、UUID 追踪等全部业务逻辑）需要 **额外的部署步骤**，因为 `user_data.sh` 在实例首次启动时执行，不适合频繁更新的应用代码。

### 18.2 部署方案

#### 方案 A：S3 中转（推荐）

通过 S3 作为应用包的中转站，EC2 从 S3 拉取最新代码。这是最简单、最可靠的方案：

1. **本地打包上传**：将 `app/` 目录打包为 tar.gz，通过 `aws s3 sync` 上传到 S3 桶
2. **EC2 拉取部署**：EC2 通过 VPC Endpoint（Gateway 类型）从 S3 下载应用包，解压并重启 pm2

**优势**：
- EC2 IAM Role 已在 Part 1（S3 模块）中配置了 S3 读取权限，无需额外授权
- 通过 VPC Endpoint 访问 S3，流量不出 VPC，无需 NAT Gateway
- 支持版本化（S3 versioning），可以快速回滚到任意历史版本

#### 方案 B：SSM Run Command

通过 AWS Systems Manager Run Command 在 EC2 上远程执行命令，适合少量文件更新或配置变更：

```bash
aws ssm send-command \
  --instance-ids "i-xxxxxxxxx" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cd /home/ec2-user/app && git pull && npm install --production && pm2 restart all"]'
```

**优势**：无需 SSH 访问，审计日志完整
**限制**：不适合传输大量文件，EC2 需安装 SSM Agent（Amazon Linux 2023 默认已安装）

#### 方案 C：CodeDeploy

通过 AWS CodeDeploy 实现自动化部署流水线，适合持续部署场景：

1. 应用包上传到 S3 或 GitHub
2. CodeDeploy 根据 `appspec.yml` 执行部署生命周期（BeforeInstall → Install → AfterInstall → ApplicationStart）
3. 支持滚动部署、蓝绿部署、自动回滚

**优势**：完整的部署生命周期管理，原生支持回滚
**限制**：需要额外配置 CodeDeploy Application + Deployment Group，对于演示环境过于重量级

### 18.3 参考脚本：`scripts/deploy-app.sh`

以下脚本实现方案 A（S3 中转）的完整部署流程——在本地打包上传应用到 S3，然后通过 SSM 在 EC2 上执行拉取和重启：

```bash
#!/bin/bash
set -euo pipefail

# ============================================================
# deploy-app.sh — Express 应用部署脚本（S3 中转 + SSM 执行）
# 用法: ./scripts/deploy-app.sh [--instance-id i-xxx] [--bucket xxx]
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/app"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_NAME="app-${TIMESTAMP}.tar.gz"

# 从 Terraform output 获取默认值（可通过命令行参数覆盖）
BUCKET="${BUCKET:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw s3_bucket_name)}"
INSTANCE_ID="${INSTANCE_ID:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw ec2_instance_id)}"
REGION="${REGION:-ap-northeast-1}"

echo "==> 打包应用目录: ${APP_DIR}"
cd "${APP_DIR}"
tar czf "/tmp/${ARCHIVE_NAME}" \
  --exclude='node_modules' \
  --exclude='.env' \
  --exclude='*.log' \
  .

echo "==> 上传到 S3: s3://${BUCKET}/deploy/${ARCHIVE_NAME}"
aws s3 cp "/tmp/${ARCHIVE_NAME}" "s3://${BUCKET}/deploy/${ARCHIVE_NAME}" --region "${REGION}"

echo "==> 通过 SSM 在 EC2 上执行部署"
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    'cd /home/ec2-user',
    'aws s3 cp s3://${BUCKET}/deploy/${ARCHIVE_NAME} /tmp/${ARCHIVE_NAME}',
    'rm -rf /home/ec2-user/app.bak && mv /home/ec2-user/app /home/ec2-user/app.bak || true',
    'mkdir -p /home/ec2-user/app && tar xzf /tmp/${ARCHIVE_NAME} -C /home/ec2-user/app',
    'cd /home/ec2-user/app && npm install --production',
    'pm2 restart all',
    'pm2 save'
  ]" \
  --region "${REGION}" \
  --query 'Command.CommandId' --output text)

echo "==> SSM Command ID: ${COMMAND_ID}"
echo "==> 等待执行完成..."
aws ssm wait command-executed \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" 2>/dev/null || true

# 查看执行结果
aws ssm get-command-invocation \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" \
  --query '{Status:Status, Output:StandardOutputContent, Error:StandardErrorContent}'

echo "==> 部署完成"
```

### 18.4 IAM 权限说明

EC2 实例的 IAM Role 在 Terraform S3 模块（Part 1）中已配置以下权限：

- `s3:GetObject` — 从 S3 桶读取应用包和静态资源
- `s3:ListBucket` — 列出桶内对象

本地执行 `deploy-app.sh` 的 IAM 用户/角色需要额外的 `ssm:SendCommand` 和 `s3:PutObject` 权限。

---

## 19. CloudFront Standard Logging

### 19.1 功能说明

CloudFront Standard Logging（标准访问日志）将每个请求的详细信息记录到 S3 桶中。日志文件以 W3C 扩展格式存储，包含时间戳、客户端 IP、请求路径、HTTP 状态码、字节数、缓存命中/未命中状态等字段。

Standard Logging 的典型用途包括：

- **流量分析**：了解各路径的请求量、热门内容、地理分布
- **缓存效率评估**：通过 `x-edge-result-type`（Hit/Miss/Error）统计缓存命中率
- **安全审计**：追踪异常请求模式、Bot 流量来源
- **性能诊断**：分析 `time-taken` 字段，定位慢请求的根因

### 19.2 配置参数

| 参数 | 值 | 说明 |
|------|-----|------|
| **Logging Bucket** | `unice-cloudfront-logs-{account_id}` | 日志专用 S3 桶，与静态资源桶分离 |
| **Prefix** | `cf-logs/` | 日志文件存储前缀，便于按分发组织 |
| **Include Cookies** | `false`（默认） | 是否在日志中记录 Cookie 值。开启会增加日志体积，仅在调试 Cookie 转发问题时按需开启 |

> 注：CloudFront 日志文件的投递存在 **数分钟到一小时** 的延迟，不适合实时监控。如果需要实时日志，应使用 CloudFront Real-time Logging（需额外配置 Kinesis Data Streams）。

### 19.3 Feature Flag

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `enable_cloudfront_logging` | `false` | 默认关闭。开启后创建日志 S3 桶并在 Distribution 中启用 Standard Logging。日志存储按 S3 标准费用计算，CloudFront 不收取额外日志费用。 |

### 19.4 对 Terraform CloudFront 模块的影响

开启 `enable_cloudfront_logging` 后，CloudFront 模块需要新增以下资源和配置：

**新增资源**：

```hcl
# 日志存储桶
resource "aws_s3_bucket" "cloudfront_logs" {
  count  = var.enable_cloudfront_logging ? 1 : 0
  bucket = "unice-cloudfront-logs-${data.aws_caller_identity.current.account_id}"
}

# 桶 ACL — CloudFront 需要 awslogsdelivery 账号的写入权限
resource "aws_s3_bucket_acl" "cloudfront_logs" {
  count  = var.enable_cloudfront_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id
  acl    = "log-delivery-write"
}

# 生命周期规则 — 90 天后转 IA，180 天后删除
resource "aws_s3_bucket_lifecycle_configuration" "cloudfront_logs" {
  count  = var.enable_cloudfront_logging ? 1 : 0
  bucket = aws_s3_bucket.cloudfront_logs[0].id

  rule {
    id     = "log-lifecycle"
    status = "Enabled"
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    expiration {
      days = 180
    }
  }
}
```

**Distribution 配置变更**：

```hcl
resource "aws_cloudfront_distribution" "main" {
  # ... 现有配置 ...

  dynamic "logging_config" {
    for_each = var.enable_cloudfront_logging ? [1] : []
    content {
      bucket          = aws_s3_bucket.cloudfront_logs[0].bucket_domain_name
      prefix          = "cf-logs/"
      include_cookies = false
    }
  }
}
```

### 19.5 费用说明

- **CloudFront 端**：Standard Logging 本身 **不产生额外 CloudFront 费用**
- **S3 端**：按标准 S3 存储和请求费用计算
  - 存储：约 $0.025/GB/月（ap-northeast-1 标准存储）
  - 写入请求：约 $0.0047/千次 PUT（由 CloudFront 写入日志文件）
- **估算**：以每日 10,000 次请求计算，每月日志量约 50-100MB，S3 费用 < $0.01/月

---

## 20. CloudFront Response Headers Policy

### 20.1 功能说明

CloudFront Response Headers Policy 允许在 CloudFront 边缘节点自动注入、修改或移除 HTTP 响应头，无需修改源站代码。这对于安全响应头尤为重要——通过 Response Headers Policy 统一管理，避免了在每个源站（S3、EC2）分别配置的麻烦，同时确保所有响应（包括缓存命中的响应）都携带正确的安全头。

### 20.2 Security Headers Policy 配置

本平台创建一个自定义 Security Headers Policy，包含以下安全响应头：

| Header | 值 | 作用 |
|--------|-----|------|
| `Strict-Transport-Security` | `max-age=63072000; includeSubDomains; preload` | **HSTS**：强制浏览器使用 HTTPS 连接，有效期 2 年，包含所有子域名，申请加入浏览器 HSTS 预加载列表 |
| `X-Content-Type-Options` | `nosniff` | 阻止浏览器对响应内容进行 MIME 类型嗅探，防止将非脚本内容当作脚本执行 |
| `X-Frame-Options` | `DENY` | 禁止页面被嵌入到 `<iframe>` 中，防止点击劫持（Clickjacking）攻击 |
| `X-XSS-Protection` | `1; mode=block` | 启用浏览器内置的 XSS 过滤器，检测到 XSS 攻击时阻止页面渲染 |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | 控制 Referer 头的发送策略：同源请求发送完整 URL，跨源请求仅发送 origin（协议+域名），降级请求（HTTPS→HTTP）不发送 |

### 20.3 Behavior 关联

Response Headers Policy 关联到以下 Cache Behavior：

| Behavior | 关联说明 |
|----------|---------|
| `Default (*)` | SSR 页面需要完整的安全头保护 |
| `/api/*` 相关 Behavior | API 响应同样需要安全头，防止通过 API 响应进行 XSS 等攻击 |
| `/static/*`、`/images/*` | 静态资源也应携带安全头，特别是 `X-Content-Type-Options` 防止 MIME 嗅探 |
| `/premium/*` | 会员内容的安全头保护 |

### 20.4 对 Terraform CloudFront 模块的影响

新增 `aws_cloudfront_response_headers_policy` 资源，并在各 Behavior 中引用：

```hcl
resource "aws_cloudfront_response_headers_policy" "security_headers" {
  count = var.enable_response_headers_policy ? 1 : 0
  name  = "unice-security-headers-policy"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    xss_protection {
      mode_block = true
      protection = true
      override   = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
  }
}
```

在 Distribution 的各 Behavior 中引用：

```hcl
# Default Behavior
default_cache_behavior {
  # ... 现有配置 ...
  response_headers_policy_id = var.enable_response_headers_policy ? aws_cloudfront_response_headers_policy.security_headers[0].id : null
}

# Ordered Behavior（以 /static/* 为例）
ordered_cache_behavior {
  path_pattern = "/static/*"
  # ... 现有配置 ...
  response_headers_policy_id = var.enable_response_headers_policy ? aws_cloudfront_response_headers_policy.security_headers[0].id : null
}
```

### 20.5 Feature Flag

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `enable_response_headers_policy` | `true` | 默认开启。安全响应头是 Web 安全最佳实践，且不产生任何额外费用。关闭后各 Behavior 不关联 Response Headers Policy。 |

### 20.6 演示价值

Response Headers Policy 是一个很好的 CloudFront 功能演示点：

- **客户痛点**：许多客户的源站缺少安全响应头，或者不同源站（S3、EC2、第三方 API）的安全头配置不一致
- **CloudFront 价值**：通过 Response Headers Policy 在边缘统一注入，一次配置覆盖所有 Behavior，无需修改任何源站代码
- **验证方法**：使用 `curl -I https://unice.keithyu.cloud/` 查看响应头，或通过浏览器 DevTools Network 面板检查

---

## 21. S3 静态资源上传自动化

### 21.1 背景

本平台的静态资源分布在两个目录中：

- **`static/`** — 图片、字体、通用静态资源和自定义错误页面
- **`app/public/`** — 前端 CSS 和 JavaScript 文件

这些文件需要上传到 S3 桶，通过 CloudFront 的 `/static/*`、`/images/*` 等 Behavior 分发。Terraform 负责创建 S3 桶和配置 OAC 策略，但文件上传作为独立的部署步骤执行，便于在不修改基础设施的情况下更新静态资源。

### 21.2 上传路径映射

| 本地路径 | S3 目标路径 | CloudFront 路径 | 说明 |
|---------|------------|----------------|------|
| `static/images/` | `s3://bucket/images/` | `/images/*` | 商品图片、Banner 图片 |
| `static/fonts/` | `s3://bucket/static/fonts/` | `/static/fonts/*` | Web 字体文件 |
| `static/assets/` | `s3://bucket/static/assets/` | `/static/assets/*` | 其他静态资源（图标、SVG 等） |
| `static/errors/` | `s3://bucket/static/errors/` | `/static/errors/*` | 自定义错误页面（403/404/500/502） |
| `app/public/css/` | `s3://bucket/static/css/` | `/static/css/*` | 样式表 |
| `app/public/js/` | `s3://bucket/static/js/` | `/static/js/*` | 前端 JavaScript |

### 21.3 参考脚本：`scripts/deploy-static.sh`

以下脚本使用 `aws s3 sync` 上传静态资源，自动设置正确的 `Content-Type` 和 `Cache-Control`：

```bash
#!/bin/bash
set -euo pipefail

# ============================================================
# deploy-static.sh — S3 静态资源上传脚本
# 用法: ./scripts/deploy-static.sh [--bucket xxx] [--invalidate]
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUCKET="${BUCKET:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw s3_bucket_name)}"
DISTRIBUTION_ID="${DISTRIBUTION_ID:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw cloudfront_distribution_id)}"
REGION="${REGION:-ap-northeast-1}"
INVALIDATE="${INVALIDATE:-false}"

echo "==> S3 Bucket: ${BUCKET}"
echo "==> Region: ${REGION}"

# ----------------------------------------------------------
# 1. 上传图片（长缓存，24 小时）
# ----------------------------------------------------------
echo "==> 上传 static/images/ → s3://${BUCKET}/images/"
aws s3 sync "${PROJECT_ROOT}/static/images/" "s3://${BUCKET}/images/" \
  --region "${REGION}" \
  --cache-control "public, max-age=86400" \
  --delete

# ----------------------------------------------------------
# 2. 上传字体（长缓存，7 天）
# ----------------------------------------------------------
echo "==> 上传 static/fonts/ → s3://${BUCKET}/static/fonts/"
aws s3 sync "${PROJECT_ROOT}/static/fonts/" "s3://${BUCKET}/static/fonts/" \
  --region "${REGION}" \
  --cache-control "public, max-age=604800" \
  --delete

# ----------------------------------------------------------
# 3. 上传通用静态资源（长缓存，24 小时）
# ----------------------------------------------------------
echo "==> 上传 static/assets/ → s3://${BUCKET}/static/assets/"
aws s3 sync "${PROJECT_ROOT}/static/assets/" "s3://${BUCKET}/static/assets/" \
  --region "${REGION}" \
  --cache-control "public, max-age=86400" \
  --delete

# ----------------------------------------------------------
# 4. 上传自定义错误页面（短缓存，5 分钟）
# ----------------------------------------------------------
echo "==> 上传 static/errors/ → s3://${BUCKET}/static/errors/"
aws s3 sync "${PROJECT_ROOT}/static/errors/" "s3://${BUCKET}/static/errors/" \
  --region "${REGION}" \
  --content-type "text/html" \
  --cache-control "public, max-age=300" \
  --delete

# ----------------------------------------------------------
# 5. 上传 CSS（中等缓存，1 小时，便于开发迭代）
# ----------------------------------------------------------
echo "==> 上传 app/public/css/ → s3://${BUCKET}/static/css/"
aws s3 sync "${PROJECT_ROOT}/app/public/css/" "s3://${BUCKET}/static/css/" \
  --region "${REGION}" \
  --content-type "text/css" \
  --cache-control "public, max-age=3600" \
  --delete

# ----------------------------------------------------------
# 6. 上传 JavaScript（中等缓存，1 小时）
# ----------------------------------------------------------
echo "==> 上传 app/public/js/ → s3://${BUCKET}/static/js/"
aws s3 sync "${PROJECT_ROOT}/app/public/js/" "s3://${BUCKET}/static/js/" \
  --region "${REGION}" \
  --content-type "application/javascript" \
  --cache-control "public, max-age=3600" \
  --delete

# ----------------------------------------------------------
# 7. 可选：触发 CloudFront 缓存失效
# ----------------------------------------------------------
if [ "${INVALIDATE}" = "true" ] || [ "${1:-}" = "--invalidate" ]; then
  echo "==> 触发 CloudFront 缓存失效: /static/* /images/*"
  aws cloudfront create-invalidation \
    --distribution-id "${DISTRIBUTION_ID}" \
    --paths "/static/*" "/images/*" \
    --region "${REGION}" \
    --query 'Invalidation.Id' --output text
  echo "==> 缓存失效已提交（传播需要数分钟）"
fi

echo "==> 静态资源上传完成"
```

### 21.4 Terraform Outputs

在 Terraform `outputs.tf` 中提供 S3 sync 命令示例，便于用户快速上手：

```hcl
output "s3_sync_commands" {
  description = "S3 静态资源上传命令示例"
  value = <<-EOT
    # 上传全部静态资源（推荐使用 deploy-static.sh 脚本）
    ./scripts/deploy-static.sh

    # 或手动上传单个目录
    aws s3 sync static/images/ s3://${aws_s3_bucket.static.id}/images/ --cache-control "public, max-age=86400"
    aws s3 sync app/public/css/ s3://${aws_s3_bucket.static.id}/static/css/ --content-type "text/css" --cache-control "public, max-age=3600"

    # 上传后触发缓存失效
    ./scripts/deploy-static.sh --invalidate
  EOT
}
