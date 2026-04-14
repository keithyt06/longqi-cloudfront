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
