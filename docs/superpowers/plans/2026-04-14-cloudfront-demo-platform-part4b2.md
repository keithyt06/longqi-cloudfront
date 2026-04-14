# CloudFront 全功能演示平台 - 实施计划 Part 4B-2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编写 2 篇 Hands-on 实操文档（07-08），覆盖 CloudFront 地理限制（Geo Restriction + WAF Geo Block）和自定义错误页面（Custom Error Response）。每篇包含完整的 AWS Console 操作步骤、配置参数、验证命令，可直接作为客户 Workshop 教材使用。

**Architecture:** 文档基于已部署的演示平台：CloudFront → VPC Origin → Internal ALB → EC2 Express，S3 (OAC) 双源架构。

**Tech Stack:** AWS CloudFront Geo Restriction, AWS WAF Geo Block, CloudFront Custom Error Response, S3 (OAC)

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

**域名:** `unice.keithyu.cloud` | **区域:** `ap-northeast-1` (东京)

**设计规格参考:** Section 6（WAF 安全防护 / Geo Block 规则）、Section 8（自定义错误页面）、Section 14（Feature Flags / enable_geo_restriction）

---

## 文件结构总览 (Part 4B-2)

```
hands-on/
├── 07-cloudfront-geo-restriction.md    # 地理限制：白名单/黑名单 + WAF Geo Block + 验证
└── 08-cloudfront-error-pages.md        # 自定义错误页面：HTML 准备 + S3 上传 + Custom Error Response + 验证
```

---

## Phase 4B-2: Hands-on 文档 07-08 (Task 17b)

### Task 17b: 地理限制 + 错误页面文档

编写 2 篇完整的 hands-on 实操文档，涵盖 CloudFront 的地理限制和自定义错误页面功能。每篇文档包含：功能原理与使用场景、AWS Console 逐步操作、curl 验证命令、常见问题排查。文档面向具备基础 AWS 经验的技术人员，可作为客户自助学习材料或 Workshop 教材。

---

### Step 17b.1: 创建 `hands-on/07-cloudfront-geo-restriction.md`

- [ ] 创建文件 `hands-on/07-cloudfront-geo-restriction.md`

```markdown
# 07 - CloudFront 地理限制：Geo Restriction 与 WAF Geo Block

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 25-35 分钟 | **难度**: 中级 | **前置要求**: 已完成 01（Distribution 创建）、已完成 04（WAF Web ACL 创建）

---

## 1. 功能概述

### 1.1 为什么需要地理限制

在电商和内容分发场景中，地理限制是常见的合规与运营需求：

- **版权合规**：视频、音乐等内容在不同国家/地区的版权授权范围不同
- **业务区域控制**：限制服务仅对目标市场开放（如仅对中国大陆 + 日本提供服务）
- **安全封禁**：屏蔽来自高风险国家/地区的恶意流量
- **法规遵从**：满足出口管制（如 OFAC 制裁国家）或数据本地化要求

### 1.2 两种地理限制方式

CloudFront 提供两种实现地理限制的方式，适用于不同场景：

| 维度 | CloudFront Geo Restriction | WAF Geo Block 规则 |
|------|--------------------------|-------------------|
| **配置位置** | CloudFront Distribution Settings | WAF Web ACL（us-east-1） |
| **限制粒度** | Distribution 全局 | 可按 Behavior/路径精细控制 |
| **模式** | 白名单（Allow List）或 黑名单（Block List） | 自定义规则，支持复杂条件组合 |
| **返回响应** | 403 Forbidden（不可自定义） | 可配置 Custom Response（自定义 HTTP 状态码和响应体） |
| **与其他条件组合** | 不支持 | 可与 IP、Header、URI 等条件组合 |
| **费用** | 无额外费用 | WAF 规则费用（$1/月/规则） |
| **生效速度** | Distribution 全球传播（3-5 分钟） | 即时生效 |
| **适用场景** | 简单的全站国家级限制 | 需要精细控制或结合其他条件的场景 |

### 1.3 地理位置检测原理

CloudFront 使用 **MaxMind GeoIP 数据库** 将访问者的源 IP 地址映射到国家/地区代码（ISO 3166-1 alpha-2）。识别结果通过以下 Header 注入到请求中：

| Header | 说明 | 示例值 |
|--------|------|--------|
| `CloudFront-Viewer-Country` | 国家代码（2 字母） | `CN`, `JP`, `US` |
| `CloudFront-Viewer-Country-Name` | 国家全名 | `China`, `Japan` |
| `CloudFront-Viewer-Country-Region` | 区域/省份代码 | `13`（东京都） |
| `CloudFront-Viewer-Country-Region-Name` | 区域/省份名称 | `Tokyo` |
| `CloudFront-Viewer-City` | 城市名 | `Tokyo` |

> **准确性说明**：MaxMind 数据库在国家级别的准确率约 99.8%，但在城市级别准确率下降到约 80%。对于使用 VPN 或代理的用户，检测到的是 VPN 出口节点的地理位置，而非用户的真实位置。

---

## 2. 方式一：CloudFront Geo Restriction（原生）

CloudFront 原生地理限制是最简单的国家级限制方案，直接在 Distribution 设置中配置。

### 步骤 1: 打开 Geo Restriction 配置

- [ ] 打开 **CloudFront Console** → 选择 Distribution（`unice.keithyu.cloud`）
- [ ] 点击 **Security** 标签
- [ ] 在 **CloudFront geographic restrictions** 部分，点击 **Edit**

### 步骤 2: 配置白名单模式（推荐用于目标市场）

白名单模式：仅允许列出的国家访问，其他国家返回 403。

- [ ] **Restriction type** 选择 **Allow list**
- [ ] 在 **Countries** 中添加允许访问的国家：

| 国家代码 | 国家 | 说明 |
|----------|------|------|
| `CN` | China | 中国大陆 |
| `JP` | Japan | 日本（平台部署区域） |
| `TW` | Taiwan | 台湾 |
| `HK` | Hong Kong | 香港 |
| `SG` | Singapore | 新加坡 |
| `US` | United States | 美国（测试用） |

- [ ] 点击 **Save changes**
- [ ] 等待 Distribution 状态变为 **Deployed**（约 3-5 分钟）

> **白名单 vs 黑名单选择建议**：
> - **白名单**（Allow list）：当你明确知道服务的目标市场时使用。例如仅面向亚太区客户，白名单列出所有亚太国家。
> - **黑名单**（Block list）：当你需要屏蔽少数高风险或受制裁国家时使用。例如屏蔽 OFAC 制裁国家列表。

### 步骤 2（备选）: 配置黑名单模式

- [ ] **Restriction type** 选择 **Block list**
- [ ] 在 **Countries** 中添加需要封禁的国家（示例）：

| 国家代码 | 国家 | 封禁原因 |
|----------|------|---------|
| `KP` | North Korea | OFAC 制裁 |
| `IR` | Iran | OFAC 制裁 |
| `SY` | Syria | OFAC 制裁 |
| `CU` | Cuba | OFAC 制裁 |

- [ ] 点击 **Save changes**

### 步骤 3: 验证 CloudFront Geo Restriction

#### 3.1 从允许的国家访问

```bash
# 从当前位置访问（假设在日本/中国/美国等白名单国家）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/api/health

# 预期输出: HTTP Status: 200
```

- [ ] 确认返回 `200`

#### 3.2 查看 CloudFront 注入的地理位置 Header

```bash
# 通过 debug 端点查看 CloudFront 检测到的地理位置
curl -s https://unice.keithyu.cloud/api/debug | jq '{
  country: .headers["cloudfront-viewer-country"],
  country_name: .headers["cloudfront-viewer-country-name"],
  region: .headers["cloudfront-viewer-country-region-name"],
  city: .headers["cloudfront-viewer-city"]
}'
```

- [ ] 确认输出中 `cloudfront-viewer-country` 与你的实际位置匹配

#### 3.3 使用 VPN 模拟被限制国家的访问

> **VPN 测试方法**：连接到一个不在白名单中的国家的 VPN 服务器（如韩国 KR，如果 KR 不在白名单中），然后重复请求：

```bash
# 连接 VPN 后测试（VPN 出口在非白名单国家）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/api/health

# 预期输出: HTTP Status: 403
```

```bash
# 查看 403 响应的详细内容
curl -s -D - https://unice.keithyu.cloud/api/health -o /dev/null 2>&1 | head -20

# 预期: CloudFront 返回默认的 403 错误页面
# 包含 "Request blocked" 或类似信息
```

- [ ] 确认被限制国家返回 `403`

#### 3.4 关闭限制（演示完毕后恢复）

- [ ] 打开 **CloudFront Console** → Distribution → **Security** → **CloudFront geographic restrictions** → **Edit**
- [ ] **Restriction type** 选择 **No restrictions**
- [ ] 点击 **Save changes**

---

## 3. 方式二：WAF Geo Block 规则（高级）

WAF Geo Block 提供更灵活的地理限制，可以与 IP、URI、Header 等条件组合，并支持自定义响应。

### 步骤 1: 打开 WAF Console

- [ ] 打开 **AWS WAF Console**（确保区域为 **US East (N. Virginia) us-east-1**）
- [ ] 左侧菜单 **Web ACLs** → 选择 `unice-demo-waf`

### 步骤 2: 创建 Geo Block 规则

- [ ] 点击 **Rules** 标签 → **Add rules** → **Add my own rules and rule groups**
- [ ] 选择 **Rule builder**

| 参数 | 值 |
|------|-----|
| Name | `GeoBlockRule` |
| Type | **Regular rule** |

- [ ] 在 **Statement** 部分配置：

| 参数 | 值 |
|------|-----|
| Inspect | **Originates from a country in** |
| Country codes | 选择需要封禁的国家（如 `KP` North Korea, `IR` Iran） |
| IP address to use to determine the country of origin | **Source IP address** |

- [ ] **Action** 选择 **Block**
- [ ] 点击 **Add rule**

### 步骤 3: 配置自定义响应（可选）

WAF 支持为 Block 动作返回自定义 HTTP 响应，比 CloudFront 原生 Geo Restriction 的默认 403 更友好：

- [ ] 在刚创建的 `GeoBlockRule` 中，点击 **Edit**
- [ ] 在 **Action** 部分，展开 **Custom response**
- [ ] 勾选 **Enable custom response**

| 参数 | 值 |
|------|-----|
| Response code | `403` |
| Custom response body | 点击 **Create new custom response body** |

- [ ] 创建自定义响应体：

| 参数 | 值 |
|------|-----|
| Name | `geo-block-response` |
| Content type | **Text/HTML** |
| Body | 见下方 HTML |

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>访问受限 - unice.keithyu.cloud</title>
    <style>
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
               display: flex; justify-content: center; align-items: center;
               min-height: 100vh; margin: 0; background: #f5f5f5; }
        .container { text-align: center; padding: 40px; background: white;
                     border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); max-width: 500px; }
        h1 { color: #e74c3c; font-size: 48px; margin-bottom: 10px; }
        p { color: #666; font-size: 16px; line-height: 1.6; }
    </style>
</head>
<body>
    <div class="container">
        <h1>403</h1>
        <p>Access Restricted</p>
        <p>Sorry, this service is not available in your region.</p>
        <p>抱歉，您所在的地区暂不支持访问本服务。</p>
    </div>
</body>
</html>
```

- [ ] 点击 **Save**
- [ ] 选择刚创建的 `geo-block-response` 作为自定义响应体
- [ ] 点击 **Save rule**

### 步骤 4: 设置规则优先级

- [ ] 确认 `GeoBlockRule` 的优先级。建议放在其他规则之后（优先级数字较大），因为地理限制通常是最后一道防线：

| 优先级 | 规则名称 | 动作 |
|--------|----------|------|
| 1 | AWSManagedRulesCommonRuleSet | Count/Block |
| 2 | AWSManagedRulesKnownBadInputsRuleSet | Block |
| 3 | AWSManagedRulesAmazonIpReputationList | Count |
| 4 | RateLimitPerIP | Block |
| 5 | **GeoBlockRule** | **Block** |

- [ ] 点击 **Save**

### 步骤 5: 高级 — 组合条件（按路径限制）

WAF 的强大之处在于可以组合多个条件。例如，只对 `/api/*` 路径实施地理限制，而静态资源全球可访问：

- [ ] 创建新规则（或编辑 `GeoBlockRule`），使用 **AND** 组合条件：

**条件 1 — 地理匹配**：

| 参数 | 值 |
|------|-----|
| Inspect | **Originates from a country in** |
| Country codes | 选择封禁国家 |

**条件 2 — 路径匹配**：

| 参数 | 值 |
|------|-----|
| Inspect | **URI path** |
| Match type | **Starts with string** |
| String to match | `/api/` |
| Text transformation | **Lowercase** |

> **效果**：只有来自封禁国家 **且** 访问 `/api/*` 路径的请求会被拦截。访问 `/static/*`、`/images/*` 等路径不受影响。

### 步骤 6: 验证 WAF Geo Block

```bash
# 正常请求（来自允许的国家）— 应返回 200
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/api/health

# 预期输出: HTTP Status: 200
```

```bash
# 查看 WAF Sampled Requests 中的 Geo Block 匹配记录
# 在 WAF Console → Web ACLs → unice-demo-waf → Overview → Sampled requests
# 筛选 Rule: GeoBlockRule，查看匹配到的请求
```

- [ ] 在 WAF Dashboard 中确认 `GeoBlockRule` 的匹配计数

```bash
# 如果使用了自定义响应，被封禁时会看到自定义 HTML
# 使用 VPN 连接到封禁国家后测试：
curl -s https://unice.keithyu.cloud/api/health

# 预期输出: 自定义 HTML 页面（"Access Restricted / 抱歉，您所在的地区暂不支持访问本服务"）
```

---

## 4. 两种方式的优先级

当同时启用 CloudFront Geo Restriction 和 WAF Geo Block 时，两者的执行顺序如下：

```
用户请求 → CloudFront Edge
              │
              ├─ ① CloudFront Geo Restriction 检查
              │     └─ 不在白名单/在黑名单 → 直接返回 403（不经过 WAF）
              │
              ├─ ② WAF 规则评估（包括 Geo Block）
              │     └─ 匹配 GeoBlockRule → 返回 Block 响应（可自定义）
              │
              └─ ③ 两者都通过 → 请求转发到 Origin
```

**关键点**：
- **CloudFront Geo Restriction 先于 WAF 执行**。如果请求被 Geo Restriction 拦截，WAF 不会看到这个请求。
- **建议二选一**：同时使用两者会增加调试复杂度。简单场景用 CloudFront 原生，需要灵活控制用 WAF。

---

## 5. 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| VPN 用户未被限制 | CloudFront 检测到的是 VPN 出口节点的国家，该国家在白名单中 | 这是地理限制的固有限制。需要更精细的检测，可考虑结合 WAF Bot Control 或第三方 IP 信誉库 |
| IP 地理位置不准确 | MaxMind 数据库更新延迟或部分 IP 段归属有误 | CloudFront 定期更新 GeoIP 数据库。如遇极端情况，可用 WAF IP Set 对已知问题 IP 做精确控制 |
| 配置白名单后自己被锁 | 忘记将自己所在国家加入白名单 | 通过 AWS CLI 直接修改 Distribution 配置（CLI 不经过 CloudFront）。或联系 AWS Support |
| CloudFront Geo Restriction 和 WAF Geo Block 冲突 | 两者同时配置且逻辑矛盾 | 建议二选一。如果 CloudFront 已限制，WAF 的 Geo Block 不会触发（请求在 CloudFront 层已被拦截） |
| 自定义错误页面未显示 | CloudFront 原生 Geo Restriction 返回自带的 403，不走 Custom Error Response 配置 | 使用 WAF Geo Block + 自定义响应，或在 CloudFront 的 Custom Error Response 中为 403 配置自定义页面（见文档 08） |
| 国家代码不确定 | 不清楚某个国家的 ISO 代码 | 参考 [ISO 3166-1 alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2) 列表，或在 Console 下拉菜单中搜索国家名 |
```

---

### Step 17b.2: 创建 `hands-on/08-cloudfront-error-pages.md`

- [ ] 创建文件 `hands-on/08-cloudfront-error-pages.md`

```markdown
# 08 - CloudFront 自定义错误页面：Custom Error Response

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 25-35 分钟 | **难度**: 中级 | **前置要求**: 已完成 01（Distribution 创建）、已完成 09 或 S3 桶已配置 OAC

---

## 1. 功能概述

### 1.1 为什么需要自定义错误页面

当 CloudFront 从源站（S3 或 ALB）收到 4xx/5xx 错误响应时，默认行为是将源站的原始错误直接返回给用户。这通常意味着：

- **403 Forbidden**：一段 XML 文本（来自 S3）或白色页面，毫无品牌感
- **404 Not Found**：nginx/express 的默认错误页面
- **502 Bad Gateway**：CloudFront 生成的简陋错误文本

对于面向客户的网站，这些裸露的错误页面会严重影响用户体验和品牌形象。

### 1.2 Custom Error Response 的工作原理

```
用户请求 → CloudFront Edge
              │
              ├─ 回源请求 → Origin 返回 4xx/5xx 错误
              │
              ├─ CloudFront 检查 Custom Error Response 配置
              │     └─ 匹配到错误码（如 404）
              │           ├─ 将请求重定向到配置的 Response Page Path（如 /static/errors/404.html）
              │           ├─ 从 S3 Origin 获取错误页面内容
              │           ├─ 替换 HTTP 状态码（可选）
              │           └─ 缓存错误响应指定 TTL
              │
              └─ 返回友好的自定义错误页面给用户
```

### 1.3 缓存行为

CloudFront 会按配置的 **Error Caching Minimum TTL** 缓存错误响应。这有两个好处：

- **减少源站压力**：同一资源的 404 请求不会每次都回源
- **提升响应速度**：错误页面从 CloudFront 边缘直接返回

但也需要注意：
- 5xx 错误的 TTL 应较短（如 60 秒），因为服务端错误通常是暂时性的
- 4xx 错误的 TTL 可以适当长一些（如 300 秒），因为资源不存在通常不会短期内改变

### 1.4 本平台的错误页面配置

| HTTP Status | 触发场景 | S3 路径 | 缓存 TTL | 返回的 HTTP 状态码 |
|---|---|---|---|---|
| 403 Forbidden | 签名 URL 过期/无效、OAC 拒绝、WAF 拦截 | `/static/errors/403.html` | 300s | 403 |
| 404 Not Found | 请求的资源不存在 | `/static/errors/404.html` | 300s | 404 |
| 500 Internal Server Error | EC2 应用异常 | `/static/errors/500.html` | 60s | 500 |
| 502 Bad Gateway | ALB 无法连接 EC2（实例未运行/端口不通） | `/static/errors/502.html` | 60s | 502 |

---

## 2. 步骤 1: 准备错误页面 HTML 文件

为 4 个错误码各创建一个品牌化的 HTML 错误页面。所有页面使用内联 CSS（不依赖外部资源），确保在任何错误场景下都能正确渲染。

### 2.1 创建 403 错误页面

- [ ] 创建文件 `/tmp/errors/403.html`

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>403 - 访问被拒绝 | unice.keithyu.cloud</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', sans-serif;
               display: flex; justify-content: center; align-items: center;
               min-height: 100vh; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
               color: #fff; }
        .container { text-align: center; padding: 40px 30px; max-width: 500px; }
        .error-code { font-size: 120px; font-weight: 800; opacity: 0.3; line-height: 1; }
        h1 { font-size: 28px; margin: 10px 0 16px; font-weight: 600; }
        p { font-size: 16px; line-height: 1.6; opacity: 0.9; margin-bottom: 12px; }
        .hint { font-size: 14px; opacity: 0.7; margin-top: 20px; }
        a { color: #fff; text-decoration: underline; }
        a:hover { opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">403</div>
        <h1>Access Denied</h1>
        <p>您没有权限访问此资源。</p>
        <p>可能的原因：签名 URL 已过期、访问受保护的内容、或被安全策略拦截。</p>
        <p class="hint"><a href="/">返回首页</a></p>
    </div>
</body>
</html>
```

### 2.2 创建 404 错误页面

- [ ] 创建文件 `/tmp/errors/404.html`

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>404 - 页面未找到 | unice.keithyu.cloud</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', sans-serif;
               display: flex; justify-content: center; align-items: center;
               min-height: 100vh; background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
               color: #fff; }
        .container { text-align: center; padding: 40px 30px; max-width: 500px; }
        .error-code { font-size: 120px; font-weight: 800; opacity: 0.3; line-height: 1; }
        h1 { font-size: 28px; margin: 10px 0 16px; font-weight: 600; }
        p { font-size: 16px; line-height: 1.6; opacity: 0.9; margin-bottom: 12px; }
        .hint { font-size: 14px; opacity: 0.7; margin-top: 20px; }
        a { color: #fff; text-decoration: underline; }
        a:hover { opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">404</div>
        <h1>Page Not Found</h1>
        <p>您访问的页面不存在或已被移除。</p>
        <p>请检查 URL 是否正确，或浏览我们的商品目录。</p>
        <p class="hint"><a href="/">返回首页</a> | <a href="/products">浏览商品</a></p>
    </div>
</body>
</html>
```

### 2.3 创建 500 错误页面

- [ ] 创建文件 `/tmp/errors/500.html`

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>500 - 服务器错误 | unice.keithyu.cloud</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', sans-serif;
               display: flex; justify-content: center; align-items: center;
               min-height: 100vh; background: linear-gradient(135deg, #4facfe 0%, #00f2fe 100%);
               color: #fff; }
        .container { text-align: center; padding: 40px 30px; max-width: 500px; }
        .error-code { font-size: 120px; font-weight: 800; opacity: 0.3; line-height: 1; }
        h1 { font-size: 28px; margin: 10px 0 16px; font-weight: 600; }
        p { font-size: 16px; line-height: 1.6; opacity: 0.9; margin-bottom: 12px; }
        .hint { font-size: 14px; opacity: 0.7; margin-top: 20px; }
        a { color: #fff; text-decoration: underline; }
        a:hover { opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">500</div>
        <h1>Internal Server Error</h1>
        <p>服务器遇到了内部错误，请稍后重试。</p>
        <p>我们的工程师已收到通知，正在紧急修复中。</p>
        <p class="hint"><a href="/">返回首页</a> | 稍后刷新页面重试</p>
    </div>
</body>
</html>
```

### 2.4 创建 502 错误页面

- [ ] 创建文件 `/tmp/errors/502.html`

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>502 - 网关错误 | unice.keithyu.cloud</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Helvetica Neue', sans-serif;
               display: flex; justify-content: center; align-items: center;
               min-height: 100vh; background: linear-gradient(135deg, #fa709a 0%, #fee140 100%);
               color: #fff; }
        .container { text-align: center; padding: 40px 30px; max-width: 500px;
                     background: rgba(0,0,0,0.2); border-radius: 12px; }
        .error-code { font-size: 120px; font-weight: 800; opacity: 0.3; line-height: 1; }
        h1 { font-size: 28px; margin: 10px 0 16px; font-weight: 600; }
        p { font-size: 16px; line-height: 1.6; opacity: 0.9; margin-bottom: 12px; }
        .hint { font-size: 14px; opacity: 0.7; margin-top: 20px; }
        a { color: #fff; text-decoration: underline; }
        a:hover { opacity: 0.8; }
    </style>
</head>
<body>
    <div class="container">
        <div class="error-code">502</div>
        <h1>Bad Gateway</h1>
        <p>无法连接到后端服务器。</p>
        <p>这通常是暂时性问题，请等待几分钟后刷新页面。</p>
        <p class="hint"><a href="/">返回首页</a> | 通常 1-2 分钟内自动恢复</p>
    </div>
</body>
</html>
```

> **设计要点**：
> - 所有 CSS 内联，不依赖外部文件（错误场景下外部资源可能也无法加载）
> - 每个错误页面使用不同的渐变色背景，便于一眼区分错误类型
> - 中英双语错误标题，适配国际化场景
> - 包含返回首页链接，引导用户回到正常页面

---

## 3. 步骤 2: 上传错误页面到 S3

将 4 个 HTML 文件上传到 S3 桶的 `/static/errors/` 路径：

```bash
# 创建本地临时目录
mkdir -p /tmp/errors

# 确认文件已准备好（上一步创建的 4 个文件）
ls -la /tmp/errors/
# 预期: 403.html, 404.html, 500.html, 502.html
```

- [ ] 逐个上传到 S3：

```bash
# 上传 403 错误页面
aws s3 cp /tmp/errors/403.html \
  s3://unice-static-keithyu-tokyo/static/errors/403.html \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=86400" \
  --region ap-northeast-1

# 上传 404 错误页面
aws s3 cp /tmp/errors/404.html \
  s3://unice-static-keithyu-tokyo/static/errors/404.html \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=86400" \
  --region ap-northeast-1

# 上传 500 错误页面
aws s3 cp /tmp/errors/500.html \
  s3://unice-static-keithyu-tokyo/static/errors/500.html \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=86400" \
  --region ap-northeast-1

# 上传 502 错误页面
aws s3 cp /tmp/errors/502.html \
  s3://unice-static-keithyu-tokyo/static/errors/502.html \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=86400" \
  --region ap-northeast-1
```

- [ ] 确认上传成功：

```bash
# 列出错误页面
aws s3 ls s3://unice-static-keithyu-tokyo/static/errors/ --region ap-northeast-1

# 预期输出:
# 2026-04-14 xx:xx:xx       xxxx 403.html
# 2026-04-14 xx:xx:xx       xxxx 404.html
# 2026-04-14 xx:xx:xx       xxxx 500.html
# 2026-04-14 xx:xx:xx       xxxx 502.html
```

- [ ] 通过 CloudFront 验证错误页面文件可正常访问（通过 OAC）：

```bash
# 直接访问错误页面文件本身（确认 S3 → OAC → CloudFront 链路正常）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/static/errors/404.html

# 预期输出: HTTP Status: 200（文件本身可以正常获取）
```

---

## 4. 步骤 3: 配置 CloudFront Custom Error Response

- [ ] 打开 **CloudFront Console** → 选择 Distribution（`unice.keithyu.cloud`）
- [ ] 点击 **Error pages** 标签
- [ ] 点击 **Create custom error response**

### 4.1 配置 403 Forbidden

- [ ] 填写配置：

| 参数 | 值 | 说明 |
|------|-----|------|
| HTTP error code | **403: Forbidden** | 触发条件 |
| Customize error response | **Yes** | 启用自定义响应 |
| Response page path | `/static/errors/403.html` | S3 上的错误页面路径 |
| HTTP response code | **403** | 返回给用户的状态码（保持 403） |
| Error caching minimum TTL (seconds) | `300` | 错误响应缓存 5 分钟 |

- [ ] 点击 **Create custom error response**

### 4.2 配置 404 Not Found

- [ ] 点击 **Create custom error response**

| 参数 | 值 | 说明 |
|------|-----|------|
| HTTP error code | **404: Not Found** | 触发条件 |
| Customize error response | **Yes** | |
| Response page path | `/static/errors/404.html` | |
| HTTP response code | **404** | 保持 404 |
| Error caching minimum TTL (seconds) | `300` | 错误响应缓存 5 分钟 |

- [ ] 点击 **Create custom error response**

### 4.3 配置 500 Internal Server Error

- [ ] 点击 **Create custom error response**

| 参数 | 值 | 说明 |
|------|-----|------|
| HTTP error code | **500: Internal Server Error** | 触发条件 |
| Customize error response | **Yes** | |
| Response page path | `/static/errors/500.html` | |
| HTTP response code | **500** | 保持 500 |
| Error caching minimum TTL (seconds) | `60` | 错误响应缓存 1 分钟（5xx 用短 TTL） |

- [ ] 点击 **Create custom error response**

### 4.4 配置 502 Bad Gateway

- [ ] 点击 **Create custom error response**

| 参数 | 值 | 说明 |
|------|-----|------|
| HTTP error code | **502: Bad Gateway** | 触发条件 |
| Customize error response | **Yes** | |
| Response page path | `/static/errors/502.html` | |
| HTTP response code | **502** | 保持 502 |
| Error caching minimum TTL (seconds) | `60` | 错误响应缓存 1 分钟（5xx 用短 TTL） |

- [ ] 点击 **Create custom error response**

### 4.5 确认配置总览

- [ ] 在 **Error pages** 标签中确认所有 4 条自定义错误响应已创建：

| HTTP Error Code | Response Page Path | HTTP Response Code | Error Caching TTL |
|---|---|---|---|
| 403 | `/static/errors/403.html` | 403 | 300s |
| 404 | `/static/errors/404.html` | 404 | 300s |
| 500 | `/static/errors/500.html` | 500 | 60s |
| 502 | `/static/errors/502.html` | 502 | 60s |

- [ ] 等待 Distribution 状态变为 **Deployed**（约 3-5 分钟）

---

## 5. 步骤 4: 验证 — 触发各种错误场景

### 5.1 触发 404 Not Found — 访问不存在的路径

```bash
# 访问一个不存在的路径
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/this-page-does-not-exist

# 预期输出: HTTP Status: 404
```

```bash
# 查看返回的自定义错误页面内容
curl -s https://unice.keithyu.cloud/this-page-does-not-exist | head -20

# 预期: 看到自定义的 404 HTML 页面（包含 "Page Not Found" 和 "您访问的页面不存在"）
```

- [ ] 确认返回 `404` 且页面内容为自定义 HTML

### 5.2 触发 403 Forbidden — 无签名访问 premium 路径

```bash
# 访问受签名保护的 premium 路径（不带签名参数）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/premium/sample-content.html

# 预期输出: HTTP Status: 403
```

```bash
# 查看 403 自定义错误页面
curl -s https://unice.keithyu.cloud/premium/sample-content.html | head -20

# 预期: 看到自定义的 403 HTML 页面（包含 "Access Denied" 和 "签名 URL 已过期"）
```

- [ ] 确认返回 `403` 且页面内容为自定义 HTML

### 5.3 触发 502 Bad Gateway — 停止 EC2 实例（可选）

> **注意**: 此测试会暂时中断服务。建议在维护窗口进行，或仅在演示环境操作。

```bash
# 获取 EC2 实例 ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=*unice*" "Name=instance-state-name,Values=running" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text --region ap-northeast-1)

echo "EC2 Instance: $INSTANCE_ID"

# 停止 EC2（模拟后端不可用）
aws ec2 stop-instances --instance-ids $INSTANCE_ID --region ap-northeast-1

# 等待 ALB 健康检查失败（约 30-60 秒）
sleep 60

# 访问动态路径（走 ALB Origin）
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/api/health

# 预期输出: HTTP Status: 502
```

```bash
# 查看 502 自定义错误页面
curl -s https://unice.keithyu.cloud/api/health | head -20

# 预期: 看到自定义的 502 HTML 页面（包含 "Bad Gateway" 和 "无法连接到后端服务器"）
```

- [ ] 确认返回 `502` 且页面内容为自定义 HTML

```bash
# 恢复 EC2 实例
aws ec2 start-instances --instance-ids $INSTANCE_ID --region ap-northeast-1

# 等待实例启动并通过 ALB 健康检查（约 2-3 分钟）
aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region ap-northeast-1
sleep 60

# 确认服务恢复
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  https://unice.keithyu.cloud/api/health

# 预期输出: HTTP Status: 200
```

- [ ] 确认 EC2 恢复后服务正常

### 5.4 验证错误页面缓存行为

```bash
# 第一次请求不存在的路径
curl -sI https://unice.keithyu.cloud/cache-test-nonexistent \
  | grep -i -E "x-cache|age"

# 预期: X-Cache: Miss from cloudfront（首次请求）
```

```bash
# 立即再次请求
curl -sI https://unice.keithyu.cloud/cache-test-nonexistent \
  | grep -i -E "x-cache|age"

# 预期:
# X-Cache: Hit from cloudfront（错误响应已被缓存）
# Age: 2（在缓存中存活了 2 秒）
```

- [ ] 确认错误响应被缓存（第二次请求显示 `Hit from cloudfront`）

```bash
# 等待 TTL 过期后再次请求（404 的 TTL 是 300 秒）
# 实际测试中可通过 CloudFront Invalidation 清除缓存
aws cloudfront create-invalidation \
  --distribution-id $(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
    --output text) \
  --paths "/cache-test-nonexistent"

echo "Invalidation created - cached error response cleared"
```

---

## 6. 高级配置

### 6.1 状态码覆盖（Response Code Override）

在某些场景下，你可能希望将源站返回的错误码映射为不同的 HTTP 状态码。例如：

- S3 返回 403（对象不存在时 OAC 场景常见）→ 映射为 **404**（对用户更友好）
- 源站返回 500 → 映射为 **503 Service Unavailable**（表示暂时不可用，客户端应重试）

配置方法：在 Custom Error Response 中，将 **HTTP response code** 设为与 **HTTP error code** 不同的值。

示例：将 S3 OAC 的 403 映射为 404

| 参数 | 值 |
|------|-----|
| HTTP error code | **403: Forbidden** |
| Response page path | `/static/errors/404.html` |
| HTTP response code | **404**（覆盖为 404） |

> **注意**: 此配置会影响 **所有** 403 错误，包括 WAF 拦截和签名 URL 过期。如果需要区分不同场景的 403，需要在应用层处理，CloudFront Custom Error Response 无法按条件区分。

### 6.2 错误页面路径的 Origin 匹配

**关键机制**：Custom Error Response 中的 Response page path（如 `/static/errors/404.html`）会按照 Distribution 的 Cache Behavior 路由规则匹配到对应的 Origin。

在本平台中：
- 路径 `/static/*` 匹配到 **S3 Origin (OAC)**
- 所以 `/static/errors/404.html` 会从 S3 桶获取

如果错误页面路径不匹配任何 Behavior，会走 **Default (*)** Behavior，可能指向 ALB Origin 而非 S3，导致错误页面无法正确加载。

**最佳实践**：错误页面路径应始终匹配到一个稳定可用的 Origin（通常是 S3）。避免将错误页面放在依赖动态后端的 Origin 上——因为当后端宕机（502/500）时，错误页面本身也无法获取。

---

## 7. 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 自定义错误页面不显示，仍返回默认错误 | Distribution 未部署完成，或 Response page path 配置错误 | 检查 Distribution 状态为 Deployed；确认路径以 `/` 开头且匹配到 S3 Origin |
| 错误页面显示 XML 内容（AccessDenied） | 错误页面路径本身返回了 403（OAC 权限问题） | 确认 S3 Bucket Policy 允许 CloudFront 访问 `/static/errors/*` 路径。通常 `/*` 通配符已覆盖 |
| 错误页面被长时间缓存，源站恢复后仍显示错误页 | Error Caching TTL 设置过长 | 降低 5xx 错误的 TTL（建议 60 秒以下）；或手动执行 Invalidation 清除缓存 |
| 5xx 错误页面不显示（返回 CloudFront 默认错误） | 错误页面的 S3 Origin 也无法访问（双重故障） | 确保 S3 桶和 OAC 配置正常。S3 是托管服务，可用性 99.99%，极少出现此问题 |
| 不同 Origin 返回的 403 想显示不同页面 | CloudFront Custom Error Response 按 HTTP 状态码匹配，无法区分 Origin | 考虑在应用层（Express）返回不同的 HTTP 状态码（如用 401 代替部分 403），然后为不同状态码配置不同错误页面 |
| OAC 场景下 S3 对象不存在返回 403 而非 404 | S3 在使用 OAC 时，对象不存在也返回 403（出于安全考虑，不泄露桶内容信息） | 可在 Custom Error Response 中将 403 映射为 404（见高级配置 6.1），但需注意会影响所有 403 场景 |
```
