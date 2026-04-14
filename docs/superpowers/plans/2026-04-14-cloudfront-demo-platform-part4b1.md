# CloudFront 全功能演示平台 - 实施计划 Part 4B-1

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编写 2 篇安全功能 hands-on 文档（05-06），覆盖 WAF Bot Control + JS SDK 集成、CloudFront 签名 URL 保护私有内容。每篇包含完整的 AWS Console 操作步骤、代码示例、curl 验证命令和常见问题排查，可直接作为客户 Workshop 教材使用。

**Architecture:** CloudFront → WAF (us-east-1) + Bot Control Targeted + JS SDK；CloudFront → Trusted Key Group → S3 /premium/* 签名 URL 保护。

**Tech Stack:** AWS WAF Bot Control, JS SDK (aws-waf-token), CloudFront Signed URL, RSA 2048 Key Pair, Trusted Key Group, Node.js @aws-sdk/cloudfront-signer

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

**域名:** `unice.keithyu.cloud` | **区域:** `ap-northeast-1` (东京)

**设计规格参考:** Section 6（WAF 安全防护 / Bot Control + JS SDK）、Section 7（签名 URL/Cookie）

---

## 文件结构总览 (Part 4B-1)

```
hands-on/
├── 05-cloudfront-waf-bot-control.md     # Bot Control Targeted + JS SDK 集成 + 验证
└── 06-cloudfront-signed-url.md          # RSA 密钥对 + Key Group + 签名 URL 生成与验证
```

---

## Phase 4B-1: Hands-on 文档 05-06 (Task 17a)

### Task 17a: Bot Control + 签名 URL 文档

编写 2 篇完整的 hands-on 实操文档，涵盖 CloudFront 的两个安全功能。每篇文档包含：功能原理与两种级别对比、AWS Console 逐步操作、完整代码示例（JS SDK / Node.js 签名）、curl 验证命令、常见问题排查。文档面向具备基础 AWS 经验的技术人员，可作为客户自助学习材料或 Workshop 教材。

---

### Step 17a.1: 创建 `hands-on/05-cloudfront-waf-bot-control.md`

- [ ] 创建文件 `hands-on/05-cloudfront-waf-bot-control.md`，完整 Bot Control + JS SDK 文档

```markdown
# 05 - CloudFront WAF Bot Control：机器人检测与 JS SDK 集成

> **演示平台**: `unice.keithyu.cloud` | **区域**: WAF 在 `us-east-1` (全球 CloudFront)
>
> **预计时间**: 40-50 分钟 | **难度**: 中高级 | **前置要求**: 已完成 04（WAF Web ACL `unice-demo-waf` 已创建并关联 CloudFront）
>
> **费用提示**: Bot Control Targeted 每月 $10 基础费 + $1/百万请求。演示完成后建议关闭以节省费用。

---

## 1. 功能概述

### 1.1 什么是 Bot Control

AWS WAF Bot Control 是 WAF 的托管规则组，专门用于检测和管理机器人（Bot）流量。它能区分合法机器人（如 Googlebot、Bingbot）和恶意机器人（爬虫、撞库工具、刷票脚本），并对不同类别的机器人执行不同的动作。

### 1.2 两个级别对比

| 维度 | Common 级别 | Targeted 级别（本平台选用） |
|------|------------|--------------------------|
| **检测方式** | HTTP 指纹（User-Agent、Header 顺序、TLS 指纹） | Common 基础上 + 行为分析 + ML 模型 |
| **能检测的 Bot** | 已知爬虫（Googlebot、SEO 工具等）、简单脚本 | 高级爬虫、无头浏览器（Puppeteer/Playwright）、自动化工具 |
| **JS SDK 集成** | 不需要 | **需要**（浏览器端收集指纹，生成 aws-waf-token） |
| **Token 验证** | 无 | 验证 aws-waf-token cookie（区分真实浏览器 vs 脚本） |
| **费用** | $1/百万请求 | **$10/月基础费** + $1/百万请求 |
| **适用场景** | 基础机器人识别、SEO 爬虫分类 | 登录页防撞库、结账页防刷单、API 防自动化滥用 |

### 1.3 JS SDK 工作流程

```
用户首次访问页面
  │
  ├─ ① 浏览器加载 WAF JS SDK (/challenge.js)
  │
  ├─ ② SDK 静默运行浏览器环境检测（约 200-500ms）
  │     ├─ Canvas 指纹
  │     ├─ WebGL 渲染特征
  │     ├─ JS 引擎特征
  │     └─ 浏览器 API 可用性检测
  │
  ├─ ③ 生成加密的 aws-waf-token cookie（有效期 5 分钟，自动续期）
  │
  ├─ ④ 后续所有请求自动携带 aws-waf-token cookie
  │
  └─ ⑤ CloudFront → WAF 验证 token：
        ├─ Token 有效 → 放行（标记为 verified_bot 或 verified_browser）
        ├─ Token 缺失/无效 → 返回 Challenge 页面（静默验证，用户无感）
        └─ Challenge 反复失败 → Block（判定为机器人）
```

**关键区分**：
- **真实浏览器（Chrome/Firefox/Safari）**：能执行 JS SDK → 生成有效 token → 通过验证
- **curl / wget / Python requests**：无法执行 JS → 无 token → 被 Challenge 或 Block
- **无头浏览器（Puppeteer）**：能执行 JS 但 SDK 检测到环境异常 → token 可能被判定为可疑

---

## 2. 前提条件

| 资源 | 说明 | 验证命令 |
|------|------|---------|
| WAF Web ACL | `unice-demo-waf` 已创建在 us-east-1 | `aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 --query "WebACLs[?Name=='unice-demo-waf'].{Id:Id,Name:Name}" --output table` |
| CloudFront Distribution | 已关联 WAF | `aws cloudfront get-distribution --id $DIST_ID --query "Distribution.DistributionConfig.WebACLId" --output text` |
| 前端页面 | Express EJS 模板可编辑 | 确认 `app/views/` 目录下有 EJS 模板文件 |

```bash
# 设置环境变量
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
  --output text)

WAF_ACL_ID=$(aws wafv2 list-web-acls --scope CLOUDFRONT --region us-east-1 \
  --query "WebACLs[?Name=='unice-demo-waf'].Id" --output text)

echo "Distribution ID: $DIST_ID"
echo "WAF ACL ID: $WAF_ACL_ID"
```

---

## 3. 操作步骤

### 步骤 1: 在 Web ACL 中添加 Bot Control 规则组

- [ ] 打开 **AWS WAF Console**（确保区域切换到 **US East (N. Virginia) us-east-1**）
- [ ] 左侧菜单 **Web ACLs** → 点击 `unice-demo-waf`
- [ ] 点击 **Rules** 标签 → **Add rules** → **Add managed rule groups**

#### 1.1 启用 Bot Control

- [ ] 展开 **AWS managed rule groups** → 向下滚动找到 **Bot Control** 分类
- [ ] 开启 **Bot Control** (AWSManagedRulesBotControlRuleSet)
- [ ] 点击 **Edit** 进入详细配置：

| 参数 | 值 | 说明 |
|------|-----|------|
| Inspection level | **Targeted** | 选择 Targeted 级别（包含行为分析 + ML） |
| Override rule group action | **No**（保持默认动作） | 各规则使用默认动作（Challenge/Block） |

> **Inspection level 说明**：
> - **Common**：仅基于 HTTP 指纹检测，不需要 JS SDK，费用较低
> - **Targeted**：在 Common 基础上增加行为分析，**需要 JS SDK 配合**，能检测更高级的机器人

- [ ] 点击 **Save rule**
- [ ] 点击 **Add rules**（返回主配置页）

#### 1.2 调整规则优先级

- [ ] 在规则列表中，将 Bot Control 规则的优先级设置为 **3**（在 Known Bad Inputs 之后）：

| 优先级 | 规则名称 | 动作 |
|--------|----------|------|
| 1 | AWSManagedRulesCommonRuleSet | Count/Block |
| 2 | AWSManagedRulesKnownBadInputsRuleSet | Block |
| **3** | **AWSManagedRulesBotControlRuleSet** | **Challenge/Block** |
| 4 | AWSManagedRulesAmazonIpReputationList | Count |
| 5 | RateLimitPerIP | Block |

- [ ] 点击 **Save**

---

### 步骤 2: 配置 Token Domain

Token Domain 决定了 JS SDK 生成的 `aws-waf-token` cookie 的作用域。必须与 CloudFront 分发的域名匹配。

- [ ] 在 `unice-demo-waf` 的详情页 → 点击 **Application integration** 标签
- [ ] 在 **Token domain list** 部分，点击 **Edit**
- [ ] 添加 Token Domain：

| 参数 | 值 |
|------|-----|
| Token domain | `unice.keithyu.cloud` |

- [ ] 点击 **Save**

> **为什么要配置 Token Domain**：
> - JS SDK 生成的 cookie 需要绑定到特定域名
> - 如果不配置，SDK 会使用 CloudFront 的默认域名（`dxxxxxxxxxx.cloudfront.net`），导致自定义域名下的请求不携带 token
> - Token Domain 必须与 CloudFront Distribution 的 CNAME（`unice.keithyu.cloud`）一致

---

### 步骤 3: 前端集成 JS SDK

WAF JS SDK 通过在浏览器端运行 JavaScript 来收集环境指纹并生成 `aws-waf-token` cookie。需要在所有前端页面的 `<head>` 中引入 SDK 脚本。

#### 3.1 获取 JS SDK 集成 URL

- [ ] 在 **Application integration** 标签页中，找到 **JavaScript SDK integration** 部分
- [ ] 复制提供的 JavaScript 集成代码（格式如下）：

```html
<script type="text/javascript" src="https://unice.keithyu.cloud/challenge.js" defer></script>
```

> **说明**：
> - `/challenge.js` 路径由 WAF 自动配置，CloudFront 会将该路径的请求路由到 WAF 的 Challenge 端点
> - `defer` 属性确保脚本不阻塞页面渲染
> - SDK 文件大小约 20-30KB（gzip 后），加载对性能影响极小

#### 3.2 在 EJS 模板中添加 SDK 引用

在所有需要 Bot Control 保护的页面模板中添加 SDK 脚本标签。

- [ ] 编辑 `app/views/` 目录下的 EJS 模板文件，在 `<head>` 标签内添加：

**方式一：逐个文件添加**

```html
<!-- app/views/index.ejs -->
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Unice - 首页</title>
  <link rel="stylesheet" href="/static/css/style.css">
  <!-- WAF Bot Control JS SDK -->
  <script type="text/javascript" src="https://unice.keithyu.cloud/challenge.js" defer></script>
</head>
```

- [ ] 对以下所有模板文件重复上述操作：

| 文件 | 页面 | 是否需要 SDK |
|------|------|-------------|
| `views/index.ejs` | 首页 | 是 |
| `views/products.ejs` | 商品列表 | 是 |
| `views/product-detail.ejs` | 商品详情 | 是 |
| `views/cart.ejs` | 购物车 | 是 |
| `views/login.ejs` | 登录/注册 | **是（重点保护）** |
| `views/debug.ejs` | 调试页 | 是 |

**方式二：使用 EJS 公共 layout（推荐）**

如果项目使用了公共 layout 模板，只需在 layout 中添加一次：

```html
<!-- app/views/layout.ejs 或 partials/head.ejs -->
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= title || 'Unice Demo' %></title>
  <link rel="stylesheet" href="/static/css/style.css">
  <!-- WAF Bot Control JS SDK - 所有页面自动加载 -->
  <script type="text/javascript" src="https://unice.keithyu.cloud/challenge.js" defer></script>
</head>
```

#### 3.3 确保 CloudFront 转发 aws-waf-token Cookie

Bot Control 依赖 `aws-waf-token` cookie 来验证请求。确认 CloudFront 的 Cache Behavior 配置正确转发此 cookie。

- [ ] 打开 **CloudFront Console** → 选择 Distribution → **Behaviors** 标签
- [ ] 检查 **Default (*)** Behavior → **Edit**
- [ ] 确认 Cache policy 中 Cookie 转发包含 `aws-waf-token`：

| 参数 | 当前配置（应为） |
|------|----------------|
| Cache policy | `PageCache`（自定义，包含 `aws-waf-token` cookie） |
| Cookie 转发 | **Include the following cookies** → `x-trace-id`, `aws-waf-token` |

> **如果使用 CachingDisabled**：该策略会自动转发所有 cookie，无需额外配置。
>
> **如果使用自定义 Cache Policy**：必须确保 `aws-waf-token` 在 cookie 转发列表中。缺少此 cookie 会导致 WAF 永远收不到 token，所有请求都被 Challenge。

- [ ] 点击 **Save changes**（如有修改）

---

### 步骤 4: 验证 Bot Control 效果

等待 Distribution 状态变为 **Deployed**（约 3-5 分钟），然后进行验证。

#### 4.1 浏览器访问 — 应通过 Challenge（真实用户）

- [ ] 在 Chrome/Firefox 浏览器中打开 `https://unice.keithyu.cloud/`
- [ ] 打开 **DevTools** (F12) → **Network** 标签
- [ ] 观察以下行为：

| 观察点 | 预期结果 |
|--------|---------|
| 页面加载 | 正常显示，无可见的 Challenge 页面 |
| `challenge.js` 请求 | Network 中可以看到加载了 `challenge.js`，状态 200 |
| Cookie | Application → Cookies 中出现 `aws-waf-token`，值为加密字符串 |
| 后续请求 | 所有请求自动携带 `aws-waf-token` cookie |

```bash
# 验证 challenge.js 可正常加载
curl -sI "https://unice.keithyu.cloud/challenge.js" | head -5

# 预期：
# HTTP/2 200
# content-type: text/javascript
# ...
```

#### 4.2 curl 访问 — 应被 Challenge 或 Block（无 JS 环境）

```bash
# 不携带 token 的 curl 请求 — 应被 Challenge (HTTP 202) 或 Block (HTTP 403)
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://unice.keithyu.cloud/"

# 预期：HTTP Status: 202（Challenge 响应）或 403（Block）
```

```bash
# 查看 Challenge 响应的完整内容
curl -s -D - "https://unice.keithyu.cloud/" | head -30

# 预期：响应体包含一个 HTML 页面（静默 Challenge），其中嵌入了 JS 脚本
# 用于在浏览器环境下自动完成验证
```

```bash
# 带有伪造 User-Agent 的请求 — 同样被拦截
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  -H "User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36" \
  "https://unice.keithyu.cloud/"

# 预期：仍然返回 202 或 403（即使 User-Agent 像真实浏览器，没有 token 仍被拦截）
```

```bash
# 对比：直接访问不受 Bot Control 保护的 API 端点（CachingDisabled Behavior）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://unice.keithyu.cloud/api/health"

# 注意：如果 /api/* 的 Behavior 也在 WAF 保护范围内，此请求同样会被 Challenge
# Bot Control 对 Web ACL 关联的所有 Behavior 生效
```

#### 4.3 查看 WAF 日志中的 Bot 标签

- [ ] 打开 **WAF Console** (us-east-1) → **Web ACLs** → `unice-demo-waf` → **Overview**
- [ ] 向下滚动到 **Sampled requests**
- [ ] 选择时间范围（Last 3 hours）
- [ ] 查看 Bot Control 标记的请求：

| 标签名称 | 含义 | 触发条件 |
|----------|------|---------|
| `awswaf:managed:aws:bot-control:bot:verified` | 已验证的合法机器人 | Googlebot、Bingbot 等已知爬虫 |
| `awswaf:managed:aws:bot-control:bot:unverified` | 未验证的机器人 | 无法确认身份的自动化工具 |
| `awswaf:managed:aws:bot-control:signal:automated_browser` | 自动化浏览器 | Puppeteer、Selenium、Playwright |
| `awswaf:managed:aws:bot-control:signal:browser_inconsistency` | 浏览器不一致 | User-Agent 与实际浏览器特征不匹配 |
| `awswaf:managed:aws:bot-control:targeted:aggregate:volumetric:session:token:absent` | Token 缺失 | 请求未携带 aws-waf-token cookie |

- [ ] 找到 curl 发出的请求 → 确认标签包含 `token:absent` 和 `bot:unverified`
- [ ] 找到浏览器发出的请求 → 确认无 Bot 相关标签或标记为正常流量

---

## 4. 高级：自定义 Bot Control 规则动作（可选）

### 4.1 对特定 Bot 类别设置不同动作

默认情况下，Bot Control 对不同类别的 Bot 使用不同的默认动作。你可以按需覆盖：

- [ ] **Web ACLs** → `unice-demo-waf` → **Rules** → 选择 `AWSManagedRulesBotControlRuleSet` → **Edit**
- [ ] 展开 **Rules** 列表，对特定规则单独设置 Override：

| 规则名称 | 默认动作 | 建议覆盖 | 说明 |
|----------|---------|---------|------|
| `CategoryHttpLibrary` | Block | Count | HTTP 库（如 Python requests），测试环境可设为 Count |
| `SignalNonBrowserUserAgent` | Challenge | Count | 非浏览器 UA，API 客户端可能触发 |
| `CategorySearchEngine` | Allow | 保持 Allow | Google/Bing 等搜索引擎，应放行 |
| `CategoryScrapingFramework` | Block | 保持 Block | 爬虫框架（Scrapy 等），应拦截 |
| `TGT_VolumetricSessionTokenAbsent` | Challenge | 保持 Challenge | 无 Token 的请求，让 Challenge 页面引导验证 |

- [ ] 点击 **Save rule**

### 4.2 为 API 端点排除 Bot Control

如果某些 API 端点需要被合法的非浏览器客户端（如移动 App、合作伙伴 API）访问，可以添加排除规则：

- [ ] 在 Web ACL 中添加一条自定义规则，优先级设在 Bot Control **之前**：

| 参数 | 值 |
|------|-----|
| Name | `AllowAPIClients` |
| Type | Regular rule |
| **If a request** | matches the statement |
| Inspect | URI path |
| Match type | Starts with string |
| String to match | `/api/health` |
| Action | **Allow** |

> 这条规则在 Bot Control 之前执行，匹配的请求直接放行，不进入 Bot Control 检测。

---

## 5. 常见问题排查

### 问题 1: aws-waf-token Cookie 过期导致页面闪烁

**现象**：用户在页面上停留超过 5 分钟后操作，短暂出现 Challenge 页面后恢复正常。

**原因**：`aws-waf-token` 有效期为 5 分钟。SDK 会自动续期，但如果用户长时间无交互（页面在后台），SDK 可能暂停续期。

**解决方案**：
- SDK 默认会在 token 过期前自动刷新，确保 `challenge.js` 的 `defer` 属性正确设置
- 对于 SPA（单页应用），确保路由切换时 SDK 仍在运行
- 如果 5 分钟太短，联系 AWS Support 调整 token TTL（默认不可自定义）

### 问题 2: CORS 错误导致 challenge.js 加载失败

**现象**：浏览器 Console 报 CORS 错误，`challenge.js` 加载失败。

**原因**：JS SDK URL 的域名与页面域名不匹配。

**解决方案**：
- 确保 `challenge.js` 的 `src` 使用与页面相同的域名（`https://unice.keithyu.cloud/challenge.js`）
- 不要使用 CloudFront 默认域名（`dxxxxxxxxxx.cloudfront.net/challenge.js`）
- 检查 Token Domain 配置是否为 `unice.keithyu.cloud`

### 问题 3: 合法请求被误报为 Bot

**现象**：正常用户的浏览器请求被 Bot Control 拦截（返回 403）。

**排查步骤**：

```bash
# 在 WAF Sampled Requests 中查找被拦截的请求
# 关注 Labels 字段，确认触发了哪条规则
```

**常见原因和解决**：
| 原因 | 解决方案 |
|------|---------|
| 用户使用了浏览器插件（如广告拦截器）阻止了 `challenge.js` 加载 | 在页面中添加提示，引导用户允许加载 SDK 脚本 |
| 企业防火墙/代理篡改了请求 Header | 将触发的规则 Override 为 Count，或添加 IP 白名单 |
| 旧版浏览器不支持 SDK 所需的 API | SDK 兼容主流浏览器（Chrome 60+、Firefox 60+、Safari 12+） |

### 问题 4: Bot Control 与缓存策略冲突

**现象**：启用 Bot Control 后，缓存命中率大幅下降。

**原因**：`aws-waf-token` cookie 被加入了 Cache Key，每个用户的 token 不同导致缓存失效。

**解决方案**：
- 确认 `aws-waf-token` 在 Cache Policy 中（必须，否则 WAF 收不到 token）
- 对于需要高缓存命中率的路径（如 `/static/*`、`/images/*`），这些 Behavior 通常使用 `CachingOptimized`（不转发 cookie），Bot Control 对这些路径仍然生效（WAF 在缓存之前执行），但不会破坏缓存
- 仅在需要 token 验证的 Behavior（Default *、/api/*）中转发 `aws-waf-token`

---

## 6. 费用与关闭

### 6.1 Bot Control 费用明细

| 计费项 | 费用 |
|--------|------|
| Bot Control Targeted 基础费 | $10/月 |
| 请求检查费 | $1/百万请求 |
| WAF Web ACL 基础费 | $5/月（已在文档 04 中计算） |

### 6.2 演示完成后关闭 Bot Control

- [ ] **Web ACLs** → `unice-demo-waf` → **Rules** 标签
- [ ] 选择 `AWSManagedRulesBotControlRuleSet` → **Delete**
- [ ] 确认删除

> 删除 Bot Control 规则后，WAF 基础防护（Common Rule Set、Known Bad Inputs、Rate Limit）仍然有效。Bot Control 可以随时重新添加。

---

## 7. CLI 快速参考

```bash
# 查看 Web ACL 中的 Bot Control 规则
aws wafv2 get-web-acl --name unice-demo-waf --scope CLOUDFRONT \
  --id $WAF_ACL_ID --region us-east-1 \
  --query "WebACL.Rules[?Name=='AWSManagedRulesBotControlRuleSet']" \
  --output json | jq .

# 查看 Token Domain 配置
aws wafv2 get-web-acl --name unice-demo-waf --scope CLOUDFRONT \
  --id $WAF_ACL_ID --region us-east-1 \
  --query "WebACL.TokenDomains" --output json

# 查看 Bot Control 匹配的请求统计
aws cloudwatch get-metric-statistics \
  --namespace AWS/WAFV2 \
  --metric-name CountedRequests \
  --dimensions Name=WebACL,Value=unice-demo-waf Name=Region,Value=us-east-1 Name=Rule,Value=AWSManagedRulesBotControlRuleSet \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum \
  --region us-east-1
```
```

---

### Step 17a.2: 创建 `hands-on/06-cloudfront-signed-url.md`

- [ ] 创建文件 `hands-on/06-cloudfront-signed-url.md`，完整签名 URL 文档

```markdown
# 06 - CloudFront 签名 URL：保护私有内容

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 35-45 分钟 | **难度**: 中级 | **前置要求**: 已完成 01（Distribution + S3 Origin + `/premium/*` Behavior 已创建）
>
> **无额外费用**: 签名 URL 功能本身不产生额外费用

---

## 1. 功能概述

### 1.1 什么是签名 URL

CloudFront 签名 URL 是一种访问控制机制，用于限制对私有内容的访问。只有持有有效签名的 URL 才能通过 CloudFront 获取受保护的内容。

**典型应用场景**：
- 付费内容下载（视频课程、电子书、软件安装包）
- 会员专属资源（高清图片、独家报告）
- 限时下载链接（分享链接 1 小时后自动失效）
- 防盗链（防止第三方网站直接引用你的资源 URL）

### 1.2 签名机制原理（RSA 非对称加密）

```
┌───────────────────────────────────────────────────────────────────┐
│                           签名流程                                 │
│                                                                   │
│   ① 生成 RSA 2048 密钥对                                          │
│      ├─ 私钥（Private Key）→ 保存在 EC2 应用服务器上                 │
│      └─ 公钥（Public Key） → 注册到 CloudFront                     │
│                                                                   │
│   ② 用户请求签名 URL                                               │
│      用户 → /api/user/signed-url → EC2 Express                    │
│              └─ Express 用私钥签名 URL + 过期时间                   │
│              └─ 返回签名 URL 给用户                                 │
│                                                                   │
│   ③ CloudFront 验证签名                                            │
│      用户用签名 URL 访问 /premium/* →                               │
│        CloudFront 用注册的公钥验证签名                               │
│        ├─ 签名有效 + 未过期 → 放行 → 返回 S3 内容                   │
│        └─ 签名无效 / 已过期 → 403 Forbidden                        │
└───────────────────────────────────────────────────────────────────┘
```

### 1.3 签名 URL vs 签名 Cookie

| 维度 | 签名 URL | 签名 Cookie |
|------|---------|------------|
| 保护粒度 | 单个文件 | 多个文件（路径模式匹配） |
| URL 是否变化 | 是（URL 包含签名参数） | 否（原始 URL 不变） |
| 适用场景 | 单文件下载、分享链接 | HLS 视频流（多 .ts 分片）、整个目录 |
| 实现复杂度 | 较低 | 较高 |

**本平台使用签名 URL**，保护 `/premium/*` 路径下的模拟会员内容。

---

## 2. 前提条件

| 资源 | 说明 | 验证命令 |
|------|------|---------|
| S3 桶 | 存放 `/premium/*` 内容 | `aws s3 ls s3://unice-static-keithyu-tokyo/premium/ --region ap-northeast-1` |
| CloudFront Distribution | `/premium/*` Behavior 已配置指向 S3 Origin | 打开 Distribution → Behaviors → 确认 `/premium/*` 存在 |
| Node.js 环境 | EC2 上已安装 Node.js 18+ | `node -v` |

```bash
# 设置环境变量
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
  --output text)

echo "Distribution ID: $DIST_ID"
```

---

## 3. 操作步骤

### 步骤 1: 生成 RSA 2048 密钥对

使用 OpenSSL 生成 RSA 非对称密钥对。私钥用于签名，公钥注册到 CloudFront 用于验证。

- [ ] 在本地或 EC2 上执行以下命令：

```bash
# 创建密钥存放目录
mkdir -p /tmp/cloudfront-keys

# 生成 RSA 2048 位私钥（PKCS#8 格式，CloudFront 要求）
openssl genrsa -out /tmp/cloudfront-keys/private_key.pem 2048

# 从私钥导出公钥
openssl rsa -pubout \
  -in /tmp/cloudfront-keys/private_key.pem \
  -out /tmp/cloudfront-keys/public_key.pem

# 验证密钥对
echo "=== 私钥信息 ==="
openssl rsa -in /tmp/cloudfront-keys/private_key.pem -text -noout | head -5

echo ""
echo "=== 公钥信息 ==="
openssl rsa -pubin -in /tmp/cloudfront-keys/public_key.pem -text -noout | head -5

echo ""
echo "=== 公钥内容（注册到 CloudFront 时使用）==="
cat /tmp/cloudfront-keys/public_key.pem
```

> **安全注意**：
> - **私钥**（`private_key.pem`）必须安全保存，仅存放在 EC2 应用服务器上。泄露私钥意味着任何人都可以伪造签名 URL
> - **公钥**（`public_key.pem`）注册到 CloudFront，可以公开
> - 生产环境建议将私钥存储在 AWS Secrets Manager 或 SSM Parameter Store 中

---

### 步骤 2: 在 CloudFront Console 创建 Public Key

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Key management** → **Public keys**
- [ ] 点击 **Create public key**

| 参数 | 值 |
|------|-----|
| Name | `unice-demo-signing-key` |
| Comment | `RSA 2048 public key for signed URL` |
| Key value | 粘贴 `public_key.pem` 的完整内容（包括 BEGIN/END 行） |

公钥内容格式示例：

```
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
（Base64 编码内容）
...
-----END PUBLIC KEY-----
```

- [ ] 点击 **Create public key**
- [ ] **记录 Public Key ID**（格式如 `K1XXXXXXXXXX`），后续步骤需要使用

```bash
# CLI 创建 Public Key
PUBLIC_KEY_ENCODED=$(cat /tmp/cloudfront-keys/public_key.pem)

CALLER_REF="unice-demo-$(date +%Y%m%d%H%M%S)"

aws cloudfront create-public-key \
  --public-key-config '{
    "CallerReference": "'$CALLER_REF'",
    "Name": "unice-demo-signing-key",
    "Comment": "RSA 2048 public key for signed URL",
    "EncodedKey": "'"$(cat /tmp/cloudfront-keys/public_key.pem)"'"
  }'

# 记录 Public Key ID
PUBLIC_KEY_ID=$(aws cloudfront list-public-keys \
  --query "PublicKeyList.Items[?Name=='unice-demo-signing-key'].Id" \
  --output text)

echo "Public Key ID: $PUBLIC_KEY_ID"
```

---

### 步骤 3: 创建 Key Group

Key Group 是一组 Public Key 的集合。CloudFront 使用 Key Group（而非单个 Key）来验证签名，支持密钥轮换——添加新密钥到 Group 后可以安全地停用旧密钥。

- [ ] 打开 **CloudFront Console** → **Key management** → **Key groups**
- [ ] 点击 **Create key group**

| 参数 | 值 |
|------|-----|
| Name | `unice-demo-key-group` |
| Comment | `Key group for unice demo signed URLs` |
| Public keys | 选择 `unice-demo-signing-key`（勾选步骤 2 创建的公钥） |

- [ ] 点击 **Create key group**

```bash
# CLI 创建 Key Group
aws cloudfront create-key-group \
  --key-group-config '{
    "Name": "unice-demo-key-group",
    "Comment": "Key group for unice demo signed URLs",
    "Items": ["'$PUBLIC_KEY_ID'"]
  }'

# 记录 Key Group ID
KEY_GROUP_ID=$(aws cloudfront list-key-groups \
  --query "KeyGroupList.Items[?KeyGroup.KeyGroupConfig.Name=='unice-demo-key-group'].KeyGroup.Id" \
  --output text)

echo "Key Group ID: $KEY_GROUP_ID"
```

---

### 步骤 4: 配置 /premium/* Behavior 的 Trusted Key Group

将 Key Group 关联到 `/premium/*` Behavior，启用签名验证。

- [ ] 打开 **CloudFront Console** → 选择 Distribution → **Behaviors** 标签
- [ ] 找到 `/premium/*` Behavior → 点击 **Edit**
- [ ] 在 **Restrict viewer access** 部分：

| 参数 | 值 |
|------|-----|
| Restrict viewer access | **Yes** |
| Trusted authorization type | **Trusted key groups (recommended)** |
| Trusted key groups | 选择 `unice-demo-key-group` |

> **Trusted key groups vs Trusted signer**：
> - **Trusted key groups（推荐）**：使用 Key Group 管理签名密钥，支持密钥轮换，IAM 权限控制
> - **Trusted signer（旧版）**：使用 AWS 账号的 CloudFront Key Pair（需要 root 账号操作），AWS 已不推荐

- [ ] 点击 **Save changes**
- [ ] 等待 Distribution 状态变为 **Deployed**

```bash
# CLI 更新 /premium/* Behavior（需要获取当前配置后修改）
# 建议通过 Console 操作，避免 CLI 配置复杂的 JSON 编辑

# 验证 Behavior 配置
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.CacheBehaviors.Items[?PathPattern=='/premium/*'].TrustedKeyGroups" \
  --output json | jq .
```

---

### 步骤 5: 上传测试内容到 /premium/*

- [ ] 上传模拟的会员内容到 S3：

```bash
# 创建测试的会员内容
cat > /tmp/premium-content.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Premium Content</title></head>
<body>
  <h1>会员专属内容</h1>
  <p>恭喜！您正在查看通过签名 URL 保护的私有内容。</p>
  <p>此页面仅对持有有效签名 URL 的用户可见。</p>
</body>
</html>
EOF

# 上传到 S3
aws s3 cp /tmp/premium-content.html \
  s3://unice-static-keithyu-tokyo/premium/exclusive-report.html \
  --content-type "text/html" \
  --region ap-northeast-1

# 确认上传成功
aws s3 ls s3://unice-static-keithyu-tokyo/premium/ --region ap-northeast-1
```

---

### 步骤 6: Node.js 生成签名 URL

使用 AWS SDK 的 `@aws-sdk/cloudfront-signer` 包生成签名 URL。

#### 6.1 安装依赖

```bash
# 在 Express 应用目录下
cd /root/keith-space/2026-project/longqi-cloudfront/app
npm install @aws-sdk/cloudfront-signer
```

#### 6.2 签名 URL 生成代码

以下是完整的签名 URL 生成示例（可集成到 Express 路由中）：

```javascript
// signed-url-generator.js
// 用于生成 CloudFront 签名 URL 的工具模块

const { getSignedUrl } = require('@aws-sdk/cloudfront-signer');
const fs = require('fs');
const path = require('path');

// 配置
const CLOUDFRONT_DOMAIN = 'https://unice.keithyu.cloud';
const KEY_PAIR_ID = 'K1XXXXXXXXXX';  // 替换为步骤 2 记录的 Public Key ID
const PRIVATE_KEY_PATH = path.join(__dirname, 'keys', 'private_key.pem');

/**
 * 生成 CloudFront 签名 URL
 * @param {string} resourcePath - 资源路径，如 '/premium/exclusive-report.html'
 * @param {number} expiresInSeconds - 过期时间（秒），默认 3600（1 小时）
 * @returns {string} 签名 URL
 */
function generateSignedUrl(resourcePath, expiresInSeconds = 3600) {
  // 读取私钥
  const privateKey = fs.readFileSync(PRIVATE_KEY_PATH, 'utf8');

  // 计算过期时间
  const expiresAt = new Date(Date.now() + expiresInSeconds * 1000);

  // 生成签名 URL
  const signedUrl = getSignedUrl({
    url: `${CLOUDFRONT_DOMAIN}${resourcePath}`,
    keyPairId: KEY_PAIR_ID,
    privateKey: privateKey,
    dateLessThan: expiresAt.toISOString(),
  });

  return signedUrl;
}

// 示例：直接运行时生成测试签名 URL
if (require.main === module) {
  const url = generateSignedUrl('/premium/exclusive-report.html', 3600);
  console.log('签名 URL（有效期 1 小时）：');
  console.log(url);
  console.log('');
  console.log('使用 curl 测试：');
  console.log(`curl -s -o /dev/null -w "HTTP Status: %{http_code}\\n" "${url}"`);
}

module.exports = { generateSignedUrl };
```

#### 6.3 集成到 Express 路由

```javascript
// routes/user.js 中添加签名 URL 端点
const { generateSignedUrl } = require('../signed-url-generator');

// GET /api/user/signed-url — 生成签名 URL（需 JWT 认证）
router.get('/signed-url', cognitoAuth, (req, res) => {
  const resourcePath = req.query.path || '/premium/exclusive-report.html';
  const expiresIn = parseInt(req.query.expires) || 3600;  // 默认 1 小时

  try {
    const signedUrl = generateSignedUrl(resourcePath, expiresIn);

    res.json({
      success: true,
      signedUrl: signedUrl,
      expiresIn: expiresIn,
      resource: resourcePath,
      generatedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error('签名 URL 生成失败:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate signed URL',
    });
  }
});
```

#### 6.4 生成测试签名 URL

```bash
# 方式一：运行 Node.js 脚本直接生成
node /root/keith-space/2026-project/longqi-cloudfront/app/signed-url-generator.js

# 方式二：通过 Express API 生成（需要 JWT 认证）
# 先登录获取 token
TOKEN=$(curl -s -X POST https://unice.keithyu.cloud/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"TestPass123!"}' | jq -r '.token')

# 生成签名 URL
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://unice.keithyu.cloud/api/user/signed-url?path=/premium/exclusive-report.html&expires=3600" | jq .
```

---

### 步骤 7: 验证签名 URL

#### 7.1 无签名访问 — 应返回 403

```bash
# 直接访问 /premium/* 路径（无签名）— 应返回 403
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://unice.keithyu.cloud/premium/exclusive-report.html"

# 预期：HTTP Status: 403
```

```bash
# 查看 403 响应内容
curl -s "https://unice.keithyu.cloud/premium/exclusive-report.html"

# 预期：CloudFront 返回 Missing Key error 或自定义 403 错误页面
# <?xml version="1.0" encoding="UTF-8"?>
# <Error><Code>MissingKey</Code><Message>Missing Key-Pair-Id query parameter or cookie value</Message></Error>
```

#### 7.2 使用签名 URL 访问 — 应返回 200

```bash
# 生成签名 URL（使用步骤 6 的 Node.js 脚本获取）
SIGNED_URL="<粘贴步骤 6.4 生成的签名 URL>"

# 使用签名 URL 访问 — 应返回 200
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "$SIGNED_URL"

# 预期：HTTP Status: 200
```

```bash
# 查看签名 URL 的内容
curl -s "$SIGNED_URL"

# 预期：返回 premium-content.html 的内容
# <h1>会员专属内容</h1>
# <p>恭喜！您正在查看通过签名 URL 保护的私有内容。</p>
```

#### 7.3 使用过期的签名 URL — 应返回 403

```bash
# 生成一个极短有效期（5 秒）的签名 URL
node -e "
const { getSignedUrl } = require('@aws-sdk/cloudfront-signer');
const fs = require('fs');
const privateKey = fs.readFileSync('/tmp/cloudfront-keys/private_key.pem', 'utf8');
const url = getSignedUrl({
  url: 'https://unice.keithyu.cloud/premium/exclusive-report.html',
  keyPairId: 'K1XXXXXXXXXX',  // 替换为实际 Public Key ID
  privateKey: privateKey,
  dateLessThan: new Date(Date.now() + 5000).toISOString(),
});
console.log(url);
" > /tmp/short-lived-url.txt

SHORT_URL=$(cat /tmp/short-lived-url.txt)

# 立即访问 — 应返回 200
curl -s -o /dev/null -w "Immediate: HTTP Status: %{http_code}\n" "$SHORT_URL"

# 等待 10 秒后访问 — 应返回 403
sleep 10
curl -s -o /dev/null -w "After 10s: HTTP Status: %{http_code}\n" "$SHORT_URL"

# 预期：
# Immediate: HTTP Status: 200
# After 10s: HTTP Status: 403
```

#### 7.4 篡改签名 URL — 应返回 403

```bash
# 篡改签名 URL 中的资源路径（尝试访问其他文件）
TAMPERED_URL=$(echo "$SIGNED_URL" | sed 's/exclusive-report.html/other-file.html/')

curl -s -o /dev/null -w "Tampered URL: HTTP Status: %{http_code}\n" "$TAMPERED_URL"

# 预期：HTTP Status: 403（签名校验失败，因为签名绑定了原始 URL）
```

---

## 4. 签名 URL 结构解析

签名后的 URL 包含以下查询参数：

```
https://unice.keithyu.cloud/premium/exclusive-report.html
  ?Expires=1744732800
  &Signature=BASE64_ENCODED_SIGNATURE
  &Key-Pair-Id=K1XXXXXXXXXX
```

| 参数 | 说明 |
|------|------|
| `Expires` | URL 过期的 Unix 时间戳（UTC） |
| `Signature` | 使用私钥对策略文档（包含 URL + 过期时间）的 RSA-SHA1 签名，Base64 编码 |
| `Key-Pair-Id` | Public Key ID，CloudFront 用此 ID 查找对应的公钥来验证签名 |

---

## 5. 常见问题排查

### 问题 1: 签名 URL 返回 403 — Access Denied

**排查步骤**：

```bash
# 检查 1: Public Key 是否已注册
aws cloudfront list-public-keys \
  --query "PublicKeyList.Items[].{Id:Id,Name:Name}" \
  --output table

# 检查 2: Key Group 是否包含正确的 Public Key
aws cloudfront list-key-groups \
  --query "KeyGroupList.Items[].KeyGroup.KeyGroupConfig.{Name:Name,Keys:Items}" \
  --output json | jq .

# 检查 3: /premium/* Behavior 是否关联了 Key Group
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.CacheBehaviors.Items[?PathPattern=='/premium/*'].{TrustedKeyGroups:TrustedKeyGroups,RestrictViewerAccess:ViewerProtocolPolicy}" \
  --output json | jq .
```

**常见原因**：
| 原因 | 解决方案 |
|------|---------|
| Key-Pair-Id 与注册的 Public Key ID 不匹配 | 确认代码中的 `keyPairId` 与 Console 中显示的 ID 一致 |
| 私钥与公钥不是同一对 | 重新从私钥导出公钥：`openssl rsa -pubout -in private_key.pem -out public_key.pem` |
| URL 已过期 | 检查 `Expires` 时间戳是否在当前时间之后 |
| Behavior 未启用 Restrict viewer access | 确认 `/premium/*` Behavior 的 Restrict viewer access 设为 Yes |

### 问题 2: PEM 格式错误

**现象**：创建 Public Key 时报错 `InvalidArgument: The public key is invalid`。

**原因和解决**：
- 确保公钥包含完整的 `-----BEGIN PUBLIC KEY-----` 和 `-----END PUBLIC KEY-----` 行
- 确保公钥没有额外的空行或空格
- 确保使用 PEM 格式（Base64 编码），不是 DER 格式

```bash
# 验证公钥格式
openssl rsa -pubin -in /tmp/cloudfront-keys/public_key.pem -noout
# 如果无错误输出，说明格式正确

# 如果密钥是 DER 格式，转换为 PEM
openssl rsa -pubin -inform DER -in public_key.der -outform PEM -out public_key.pem
```

### 问题 3: 签名 URL 中文件名包含特殊字符

**现象**：资源路径包含中文、空格或特殊字符时签名验证失败。

**解决方案**：
- 在签名时对 URL 进行正确的 URI 编码
- 确保签名时使用的 URL 与实际访问的 URL 完全一致（包括编码方式）

```javascript
// 对包含特殊字符的路径进行编码
const resourcePath = encodeURI('/premium/报告-2026.pdf');
const signedUrl = generateSignedUrl(resourcePath, 3600);
```

### 问题 4: 密钥轮换

**场景**：需要更换签名密钥（定期轮换或私钥泄露）。

**步骤**：
1. 生成新的 RSA 密钥对
2. 在 CloudFront 创建新的 Public Key
3. 将新 Public Key 添加到现有 Key Group（此时 Key Group 包含新旧两个 Key）
4. 更新 EC2 应用，使用新私钥签名
5. 等待所有已发放的旧签名 URL 过期
6. 从 Key Group 中移除旧 Public Key
7. 删除旧 Public Key

> **关键**：步骤 3 和 4 之间 Key Group 同时包含新旧两个 Key，确保过渡期内新旧签名 URL 都能验证通过。

---

## 6. 签名 URL 完整配置对照表

| 配置项 | 值 | 说明 |
|--------|-----|------|
| 密钥算法 | RSA 2048 | CloudFront 支持 1024/2048/4096，推荐 2048 |
| Public Key | `unice-demo-signing-key` | 注册到 CloudFront |
| Key Group | `unice-demo-key-group` | 包含 1 个 Public Key |
| 保护路径 | `/premium/*` | S3 上的会员内容 |
| 签名端点 | `/api/user/signed-url` | 需 JWT 认证才能调用 |
| URL 有效期 | 3600 秒（1 小时） | 可在请求时自定义 |
| IP 限制 | 无 | 可选：签名策略中指定允许的客户端 IP |

---

## 7. CLI 快速参考

```bash
# 列出所有 Public Keys
aws cloudfront list-public-keys \
  --query "PublicKeyList.Items[].{Id:Id,Name:Name,CreatedTime:CreatedTime}" \
  --output table

# 查看 Public Key 详情
aws cloudfront get-public-key --id $PUBLIC_KEY_ID

# 列出所有 Key Groups
aws cloudfront list-key-groups \
  --query "KeyGroupList.Items[].KeyGroup.{Id:Id,Name:KeyGroupConfig.Name,Keys:KeyGroupConfig.Items}" \
  --output table

# 查看 /premium/* Behavior 的签名配置
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.CacheBehaviors.Items[?PathPattern=='/premium/*'].{Restricted:Restrict,TrustedKeyGroups:TrustedKeyGroups}" \
  --output json | jq .

# 删除 Public Key（先从 Key Group 移除）
# aws cloudfront delete-public-key --id $PUBLIC_KEY_ID --if-match $ETAG

# 删除 Key Group（先从 Behavior 移除）
# aws cloudfront delete-key-group --id $KEY_GROUP_ID --if-match $ETAG
```
```
