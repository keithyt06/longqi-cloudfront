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
