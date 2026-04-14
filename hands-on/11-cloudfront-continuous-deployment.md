# 11 - CloudFront Continuous Deployment 灰度发布

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 60 分钟 | **难度**: 高级 | **前置要求**: 已完成 01（Distribution 创建）、Distribution 已稳定运行

---

## 1. 功能概述

### 1.1 什么是 Continuous Deployment

CloudFront Continuous Deployment（持续部署）是 CloudFront 的灰度发布功能，允许你在 **不影响生产流量** 的情况下安全地测试 CloudFront 配置变更。

**核心机制**：创建一个与 Production Distribution 完全独立的 **Staging Distribution**，然后通过 **Continuous Deployment Policy** 将一部分真实流量（基于权重或特定 Header）路由到 Staging 进行验证。

### 1.2 为什么需要灰度发布

CloudFront 配置变更的传统痛点：

| 痛点 | 传统方式 | Continuous Deployment |
|------|---------|----------------------|
| **变更影响范围** | 100% 用户立即生效 | 仅影响 5%（或指定 Header）用户 |
| **验证时间** | 上线后才能验证 | 上线前用真实流量验证 |
| **回滚速度** | 修改 Distribution → 等待 3-5 分钟全球传播 | 禁用 Staging → 即刻回滚 |
| **风险** | 配置错误影响所有用户 | 最差情况只影响 5% 用户 |
| **信心** | "上线前祈祷" | "数据驱动的决策" |

### 1.3 Staging vs Production 概念

```
                      ┌─────────────────────────┐
                      │ Continuous Deployment    │
                      │ Policy                   │
                      │                          │
                      │ 策略类型:                 │
                      │ ├ SingleWeight (5%)       │
                      │ │ 按权重随机分流           │
                      │ └ SingleHeader            │
                      │   指定 Header 匹配分流     │
                      └──────┬──────────┬────────┘
                             │          │
                      95% 流量    5% 流量 (或 Header 匹配)
                             │          │
                             ▼          ▼
                    ┌──────────┐  ┌──────────┐
                    │Production│  │ Staging  │
                    │ Dist.    │  │ Dist.    │
                    │          │  │          │
                    │ 当前稳定  │  │ 测试新配置│
                    │ 配置     │  │ (如新的   │
                    │          │  │ Cache TTL │
                    │          │  │ / Function│
                    │          │  │ / WAF 规则│
                    │          │  │ )         │
                    └──────────┘  └──────────┘

验证通过 → Promote：Staging 配置提升为 Production
验证失败 → 禁用 Staging：所有流量回到 Production
```

**关键要点**：
- Staging Distribution 和 Production Distribution **共享同一个域名**（`unice.keithyu.cloud`），用户无感知
- CloudFront 边缘节点根据 Policy 决定每个请求送往哪个 Distribution
- Staging Distribution 的 CloudFront 请求费用单独计费

### 1.4 两种分流策略

| 策略 | 说明 | 适用场景 |
|------|------|---------|
| **SingleWeight** | 按权重随机分配流量百分比（如 5%） | 验证对真实用户的影响、A/B 对比测试 |
| **SingleHeader** | 请求包含指定 Header 时路由到 Staging | 开发/测试人员主动测试、精确控制测试范围 |

---

## 2. 前提条件

| 资源 | 说明 | 验证命令 |
|------|------|---------|
| Production Distribution | 已稳定运行 | `aws cloudfront get-distribution --id $DIST_ID --query "Distribution.{Status:Status,DomainName:DomainName}" --output table` |
| 自定义域名 | `unice.keithyu.cloud` 已配置 | `curl -sI https://unice.keithyu.cloud/ \| grep -i "x-cache"` |
| ACM 证书 | `*.keithyu.cloud` 在 us-east-1 | `aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2 --query "Certificate.Status" --output text --region us-east-1` |

```bash
# 设置环境变量（后续步骤使用）
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
  --output text)

echo "Production Distribution ID: $DIST_ID"
```

---

## 3. 操作步骤

### 步骤 1: 导出 Production Distribution 配置

首先导出当前 Production 的完整配置，作为 Staging Distribution 的基础：

```bash
# 获取 Production Distribution 的完整配置
aws cloudfront get-distribution-config --id $DIST_ID \
  --output json > /tmp/prod-dist-config.json

# 提取 ETag（后续 API 调用需要）
PROD_ETAG=$(aws cloudfront get-distribution-config --id $DIST_ID \
  --query "ETag" --output text)

echo "Production ETag: $PROD_ETAG"

# 查看当前配置概要
cat /tmp/prod-dist-config.json | jq '.DistributionConfig | {
  Origins: .Origins.Items[].DomainName,
  DefaultCacheBehavior: .DefaultCacheBehavior.ViewerProtocolPolicy,
  PriceClass: .PriceClass,
  Enabled: .Enabled
}'
```

### 步骤 2: 在 Console 中创建 Staging Distribution

1. 打开 [CloudFront Console](https://console.aws.amazon.com/cloudfront/)
2. 点击你的 Production Distribution（`unice.keithyu.cloud`）
3. 点击 **Continuous deployment** 选项卡
4. 点击 **Create staging distribution** 按钮

> Console 会自动基于 Production 的配置创建 Staging Distribution，所有 Origin、Behavior、Function、WAF 关联等配置完全相同。

5. 等待 Staging Distribution 创建完成（状态变为 `Deployed`，通常 5-10 分钟）

```bash
# 查看 Staging Distribution
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Staging==\`true\`].{Id:Id,Status:Status,DomainName:DomainName,Staging:Staging}" \
  --output table

# 记录 Staging Distribution ID
STAGING_DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Staging==\`true\`].Id" \
  --output text)

echo "Staging Distribution ID: $STAGING_DIST_ID"
```

### 步骤 3: 创建 Continuous Deployment Policy（SingleWeight 5%）

1. 在 **Continuous deployment** 选项卡中，点击 **Create policy** 按钮
2. 配置分流策略：

| 配置项 | 值 | 说明 |
|-------|---|------|
| **Traffic configuration** | `SingleWeight` | 按权重分流 |
| **Weight** | `5` (即 5%) | 5% 的真实流量路由到 Staging |
| **Session stickiness** | 启用 | 同一用户的后续请求继续送往同一个 Distribution（避免用户在两个版本间跳来跳去） |
| **Idle TTL** | `300` (秒) | Session 粘性保持 5 分钟 |

3. 点击 **Create policy**
4. 系统会提示 **Enable policy**，点击确认启用

```bash
# CLI 创建 Continuous Deployment Policy
# 首先获取 Staging Distribution 域名
STAGING_DOMAIN=$(aws cloudfront get-distribution --id $STAGING_DIST_ID \
  --query "Distribution.DomainName" --output text)

echo "Staging Domain: $STAGING_DOMAIN"

# 创建 Continuous Deployment Policy
aws cloudfront create-continuous-deployment-policy \
  --continuous-deployment-policy-config '{
    "StagingDistributionDnsNames": {
      "Quantity": 1,
      "Items": ["'$STAGING_DOMAIN'"]
    },
    "Enabled": true,
    "TrafficConfig": {
      "SingleWeightConfig": {
        "Weight": 0.05,
        "SessionStickinessConfig": {
          "IdleTTL": 300,
          "MaximumTTL": 600
        }
      },
      "Type": "SingleWeight"
    }
  }'

echo "Continuous Deployment Policy created with 5% weight"
```

> **Session stickiness 解释**：启用后，CloudFront 会在用户首次请求时通过 `Set-Cookie` 设置一个持久化的粘性 cookie。后续请求带上此 cookie 后，CloudFront 会将用户持续路由到同一个 Distribution（Production 或 Staging），避免用户在两个版本之间随机切换导致体验不一致。

### 步骤 4: 在 Staging 上修改配置（模拟变更）

为了演示灰度发布，在 Staging Distribution 上做一个可观察的配置变更。我们修改 Default Behavior 的自定义响应 Header：

1. 在 CloudFront Console 中，点击 **Staging Distribution**
2. 点击 **Behaviors** 选项卡
3. 选择 **Default (*)** Behavior，点击 **Edit**
4. 在 **Response headers policy** 部分，点击 **Create policy**（或使用已有的自定义策略）
5. 添加一个自定义 Header：

| Header name | Value | Override origin |
|------------|-------|----------------|
| `X-CloudFront-Version` | `staging-v2` | Yes |

6. 保存并等待 Staging 部署完成

> **为什么选择 Response Header**：这个变更不影响功能，但可以通过 `curl -I` 清楚地看到请求被 Production 还是 Staging 处理。

也可以用 CLI 在 Staging 上修改一个不同的配置，例如修改 `/api/products*` 的缓存 TTL：

```bash
# 获取 Staging Distribution 配置
aws cloudfront get-distribution-config --id $STAGING_DIST_ID \
  --output json > /tmp/staging-config.json

# 查看当前配置（用于对比修改前后）
cat /tmp/staging-config.json | jq '.DistributionConfig.DefaultCacheBehavior'
```

### 步骤 5: 验证分流生效

#### 方法 A: 观察 SingleWeight 分流（5% 随机）

```bash
# 发送 20 次请求，统计被 Staging 处理的比例
echo "=== Testing SingleWeight traffic split ==="
STAGING_COUNT=0
PROD_COUNT=0

for i in $(seq 1 20); do
  RESPONSE=$(curl -s -D - "https://unice.keithyu.cloud/api/health" -o /dev/null 2>&1)

  if echo "$RESPONSE" | grep -q "X-CloudFront-Version: staging-v2"; then
    STAGING_COUNT=$((STAGING_COUNT + 1))
    echo "Request $i: → Staging"
  else
    PROD_COUNT=$((PROD_COUNT + 1))
    echo "Request $i: → Production"
  fi
done

echo ""
echo "Results: Production=$PROD_COUNT, Staging=$STAGING_COUNT (expected ~5% Staging)"
```

> **注意**：由于 Session stickiness，如果你的第一个请求被分配到 Production，后续请求也会继续走 Production（5 分钟内）。要测试分流效果，可以等待 Idle TTL 过期，或使用不同的 IP/浏览器。

#### 方法 B: 使用 Header 精确测试 Staging

如果你同时配置了 SingleHeader 策略（或想直接测试 Staging），可以通过添加特定 Header 强制路由到 Staging：

```bash
# 不带 Header — 走 Production
curl -sI "https://unice.keithyu.cloud/api/health" | grep -i "x-cloudfront-version"
# 预期: 无该 header（Production 没有添加）

# 带 Staging Header — 走 Staging
curl -sI -H "aws-cf-cd-staging: true" "https://unice.keithyu.cloud/api/health" | grep -i "x-cloudfront-version"
# 预期: X-CloudFront-Version: staging-v2
```

> **`aws-cf-cd-staging` Header**：这是 CloudFront Continuous Deployment 的保留 Header 名称。当 Policy 类型为 SingleHeader 时，包含此 Header 且值匹配的请求会被路由到 Staging。

### 步骤 6: 监控和对比

在灰度期间，对比 Production 和 Staging 的关键指标：

```bash
# 查看 Production Distribution 的请求统计
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=$DIST_ID Name=Region,Value=Global \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-east-1

# 查看 Staging Distribution 的请求统计
aws cloudwatch get-metric-statistics \
  --namespace AWS/CloudFront \
  --metric-name Requests \
  --dimensions Name=DistributionId,Value=$STAGING_DIST_ID Name=Region,Value=Global \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-east-1
```

**关键对比指标**：

| 指标 | CloudWatch Metric | 说明 |
|------|------------------|------|
| 错误率 | `4xxErrorRate`, `5xxErrorRate` | Staging 的错误率不应高于 Production |
| 缓存命中率 | `CacheHitRate` | 修改缓存策略时重点关注 |
| 请求延迟 | `OriginLatency` | Staging 的回源延迟应与 Production 相当 |
| 请求量 | `Requests` | 验证分流比例是否符合预期（~5%） |

### 步骤 7: Promote — 将 Staging 配置提升为 Production

验证通过后，将 Staging 的配置提升为 Production：

**在 Console 中操作**：

1. 打开 Production Distribution
2. 点击 **Continuous deployment** 选项卡
3. 点击 **Promote** 按钮
4. 确认对话框中点击 **Promote**

> Promote 操作会：
> 1. 将 Staging Distribution 的配置复制到 Production Distribution
> 2. 禁用 Continuous Deployment Policy（所有流量回到 Production）
> 3. 删除 Staging Distribution
>
> 整个过程通常需要 5-10 分钟完成全球传播。

```bash
# CLI Promote（更新 Production Distribution 使用 Staging 的配置）
# 获取 Staging 的完整配置
aws cloudfront get-distribution-config --id $STAGING_DIST_ID \
  --output json > /tmp/staging-final-config.json

# 获取 Production 的 ETag
PROD_ETAG=$(aws cloudfront get-distribution-config --id $DIST_ID \
  --query "ETag" --output text)

# 使用 Staging 配置更新 Production
# 注意：需要将 staging-specific 字段移除（如 staging: true）
# 实际操作中建议使用 Console 的 Promote 按钮

echo "Promoting Staging to Production..."
echo "Production ETag: $PROD_ETAG"
echo "Please use Console 'Promote' button for safety"
```

### 步骤 8: 回滚 — 如果出现问题

如果在灰度期间发现 Staging 有问题，可以立即回滚：

**在 Console 中操作**：

1. 打开 Production Distribution → **Continuous deployment** 选项卡
2. 点击 **Disable policy** 按钮
3. 确认禁用

> 禁用 Policy 后，100% 的流量立即回到 Production Distribution。Staging Distribution 仍然存在，可以修复后重新启用 Policy。

```bash
# CLI 禁用 Continuous Deployment Policy
# 获取 Policy ID
CD_POLICY_ID=$(aws cloudfront list-continuous-deployment-policies \
  --query "ContinuousDeploymentPolicyList.Items[0].ContinuousDeploymentPolicy.Id" \
  --output text)

CD_POLICY_ETAG=$(aws cloudfront get-continuous-deployment-policy --id $CD_POLICY_ID \
  --query "ETag" --output text)

echo "Disabling Continuous Deployment Policy: $CD_POLICY_ID"

# 获取当前配置并禁用
aws cloudfront get-continuous-deployment-policy-config --id $CD_POLICY_ID \
  --output json | jq '.ContinuousDeploymentPolicyConfig.Enabled = false' | \
  jq '.ContinuousDeploymentPolicyConfig' > /tmp/cd-policy-disabled.json

aws cloudfront update-continuous-deployment-policy \
  --id $CD_POLICY_ID \
  --if-match $CD_POLICY_ETAG \
  --continuous-deployment-policy-config file:///tmp/cd-policy-disabled.json

echo "Policy disabled - all traffic now goes to Production"
```

---

## 4. 完整演示场景

### 场景 A: 缓存策略变更

**目标**：将 `/api/products*` 的缓存 TTL 从 3600s 改为 7200s

1. 创建 Staging Distribution（继承 Production 配置）
2. 在 Staging 修改 `/api/products*` Behavior 的 Cache Policy TTL → 7200s
3. 创建 CD Policy（SingleWeight 5%）
4. 观察 1 小时，对比 Production 和 Staging 的 CacheHitRate
5. 若 Staging CacheHitRate 提升且无错误 → Promote
6. 若出现问题 → 禁用 Policy 回滚

### 场景 B: 新增 CloudFront Function

**目标**：在 Staging 上测试新的 URL 重写规则

1. 创建 Staging Distribution
2. 在 Staging 的 Default Behavior 上关联新的 CloudFront Function
3. 创建 CD Policy（SingleHeader，Header: `aws-cf-cd-staging: true`）
4. 测试人员手动添加 Header 验证重写逻辑
5. 验证通过 → 切换为 SingleWeight 5% 灰度
6. 观察稳定 → Promote

### 场景 C: WAF 规则从 Count 切换为 Block

**目标**：将 Common Rule Set 从 Count 模式切换为 Block 模式

1. 创建 Staging Distribution
2. 在 Staging 关联的 WAF Web ACL 中将规则改为 Block（注意：WAF ACL 是共享的，需要为 Staging 创建独立的 Web ACL，或使用 Rule-level override）
3. 创建 CD Policy（SingleWeight 5%）
4. 监控 Staging 的 WAF BlockedRequests 指标和 5xxErrorRate
5. 确认无误报 → Promote

---

## 5. 注意事项与限制

| 项目 | 说明 |
|------|------|
| **费用** | Staging Distribution 的请求量单独计费（与 Production 相同的费率） |
| **自定义域名** | Staging 共享 Production 的自定义域名，不能使用不同域名 |
| **一对一** | 每个 Production Distribution 同一时间只能关联一个 Staging Distribution |
| **WAF** | Staging 可以关联不同的 WAF Web ACL（在 us-east-1 创建独立 ACL） |
| **Origin** | Staging 和 Production 使用相同的 Origin（S3 桶、ALB），无法指向不同后端 |
| **Function** | Staging 可以关联不同的 CloudFront Function 或 Lambda@Edge |
| **证书** | Staging 使用与 Production 相同的 ACM 证书 |
| **Session stickiness** | 建议启用，避免用户在两个版本间反复切换 |

---

## 6. 常见问题排查

### 问题 1: 无法创建 Staging Distribution

```bash
# 检查 Production Distribution 是否已有关联的 Staging
aws cloudfront get-distribution --id $DIST_ID \
  --query "Distribution.DistributionConfig.ContinuousDeploymentPolicyId" \
  --output text
```

**常见原因**：
- Production Distribution 已关联一个 Staging（一对一限制）
- Production Distribution 状态不是 `Deployed`
- IAM 权限不足（需要 `cloudfront:CreateDistribution` 和 `cloudfront:CreateContinuousDeploymentPolicy`）

### 问题 2: 分流比例不符合预期

**分析**：
- Session stickiness 会导致短期内的比例偏差（用户被"粘"在某个版本上）
- 5% 的权重在小流量场景下统计波动大，需要足够的请求量才能稳定在 5%
- 确认 CD Policy 已启用（`Enabled: true`）

```bash
# 检查 CD Policy 状态
aws cloudfront get-continuous-deployment-policy --id $CD_POLICY_ID \
  --query "ContinuousDeploymentPolicy.ContinuousDeploymentPolicyConfig.{Enabled:Enabled,Weight:TrafficConfig.SingleWeightConfig.Weight}" \
  --output table
```

### 问题 3: Promote 后配置未生效

```bash
# 检查 Production Distribution 状态
aws cloudfront get-distribution --id $DIST_ID \
  --query "Distribution.{Status:Status,LastModifiedTime:LastModifiedTime}" \
  --output table

# 如果状态是 InProgress，等待部署完成
aws cloudfront wait distribution-deployed --id $DIST_ID
```

**注意**：Promote 后全球传播需要 3-5 分钟。在此期间，不同 PoP 可能返回新旧两个版本的配置。

---

## 7. 清理

演示结束后，清理 Staging 资源以避免额外费用：

```bash
# 1. 禁用 Continuous Deployment Policy
CD_POLICY_ID=$(aws cloudfront list-continuous-deployment-policies \
  --query "ContinuousDeploymentPolicyList.Items[0].ContinuousDeploymentPolicy.Id" \
  --output text)

if [ "$CD_POLICY_ID" != "None" ] && [ -n "$CD_POLICY_ID" ]; then
  CD_ETAG=$(aws cloudfront get-continuous-deployment-policy --id $CD_POLICY_ID \
    --query "ETag" --output text)

  echo "Disabling CD Policy: $CD_POLICY_ID"
  # 禁用 Policy（先获取配置，设置 Enabled=false，再更新）
fi

# 2. 解除 Production 与 Staging 的关联
echo "Detach Staging from Production via Console: Distribution → Continuous deployment → Delete"

# 3. 禁用并删除 Staging Distribution
if [ -n "$STAGING_DIST_ID" ]; then
  echo "Staging Distribution to clean up: $STAGING_DIST_ID"
  echo "Steps: Disable Staging → Wait for Deployed → Delete Staging"
fi

# 4. 删除 Continuous Deployment Policy
echo "Delete CD Policy after Staging is deleted"
```

---

## 8. CLI 快速参考

```bash
# 列出所有 Continuous Deployment Policy
aws cloudfront list-continuous-deployment-policies \
  --query "ContinuousDeploymentPolicyList.Items[].ContinuousDeploymentPolicy.{Id:Id,Enabled:ContinuousDeploymentPolicyConfig.Enabled}" \
  --output table

# 查看 CD Policy 详情
aws cloudfront get-continuous-deployment-policy --id YOUR_POLICY_ID

# 列出 Staging Distribution
aws cloudfront list-distributions \
  --query "DistributionList.Items[?Staging==\`true\`].{Id:Id,Status:Status,Domain:DomainName}" \
  --output table

# 查看 Staging Distribution 配置
aws cloudfront get-distribution-config --id $STAGING_DIST_ID --output json | jq .

# 查看 Production 关联的 CD Policy
aws cloudfront get-distribution --id $DIST_ID \
  --query "Distribution.DistributionConfig.ContinuousDeploymentPolicyId" \
  --output text
```
