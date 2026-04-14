# 10 - CloudFront VPC Origin 全内网架构

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 45 分钟 | **难度**: 高级 | **前置要求**: 已完成 01（Distribution 创建）、Internal ALB 已部署

---

## 1. 功能概述

### 1.1 什么是 VPC Origin

CloudFront VPC Origin 是 2024 年 11 月发布的新功能，允许 CloudFront **直接连接 VPC 内的私有资源**（Internal ALB、Internal NLB、EC2 实例），无需通过公网。这从根本上解决了"如何防止用户绕过 CDN 直接攻击源站"的安全难题。

**传统架构的问题**：

```
传统方案 (Public ALB):
用户 → CloudFront → 公网 → Public ALB → EC2
                       ↑
攻击者 → 绕过 CF 直连 ALB（暴露公网 IP）
```

**VPC Origin 架构**：

```
VPC Origin 方案 (Internal ALB):
用户 → CloudFront → VPC Origin ENI → Internal ALB → EC2
                                          ↑
                                    无公网 IP，攻击者无法直连
```

### 1.2 工作原理

VPC Origin 的核心机制是在你的 VPC 内创建 **Elastic Network Interface (ENI)**：

1. **创建 VPC Origin 时**：CloudFront 在你指定的子网中创建 ENI（弹性网络接口）
2. **ENI 归属**：ENI 由 CloudFront 服务管理，绑定你指定的安全组
3. **流量路径**：CloudFront Edge 通过 AWS 内部网络将请求发送到 ENI → ENI 在 VPC 内部转发到 Internal ALB → ALB 转发到 EC2
4. **安全组控制**：ALB 安全组仅允许来自 VPC Origin 安全组的入站流量，形成严格的访问链

```
┌───────────────────────────────────────────────────────────────────┐
│ CloudFront Edge (全球 600+ PoP)                                    │
│                                                                   │
│   ① 用户请求到达最近的 CloudFront PoP                               │
│   ② 缓存未命中 → 回源请求                                          │
│   ③ 通过 AWS 骨干网络（非公网）送达 VPC                              │
└──────────────────────────┬────────────────────────────────────────┘
                           │ AWS 内部网络
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│ VPC: vpc-086e15047c7f68e87                                        │
│                                                                   │
│  ┌──────────────────────┐                                         │
│  │ VPC Origin ENI        │  ← CloudFront 创建的 ENI               │
│  │ SG: vpc-origin-sg     │  ← 出站: 仅 ALB SG port 80            │
│  └───────────┬──────────┘                                         │
│              │ VPC 内部流量 (port 80)                               │
│              ▼                                                     │
│  ┌──────────────────────┐                                         │
│  │ Internal ALB          │  ← 入站: 仅 VPC Origin SG port 80     │
│  │ SG: alb-sg            │  ← 出站: 仅 EC2 SG port 3000          │
│  │ (Private Subnet)      │                                        │
│  └───────────┬──────────┘                                         │
│              │ VPC 内部流量 (port 3000)                             │
│              ▼                                                     │
│  ┌──────────────────────┐                                         │
│  │ EC2 Express            │  ← 入站: 仅 ALB SG port 3000         │
│  │ SG: ec2-sg             │                                       │
│  │ (Private Subnet)       │                                       │
│  └──────────────────────┘                                         │
└──────────────────────────────────────────────────────────────────┘
```

### 1.3 VPC Origin vs 传统公网 Origin 对比

| 维度 | Public ALB Origin | VPC Origin (Internal ALB) |
|------|-------------------|--------------------------|
| **ALB 类型** | Internet-facing（公网 IP） | Internal（仅内网 IP） |
| **源站暴露** | 公网可直连 ALB IP | 无公网入口，完全隔离 |
| **绕过 CDN 风险** | 高（攻击者可查 DNS 找到 ALB IP） | 无（ALB 无公网 DNS/IP） |
| **DDoS 防护** | 需额外配置 Shield/SG | 天然免疫（流量必经 CloudFront） |
| **NAT Gateway** | 不需要（ALB 有公网） | 回源走 AWS 内网，不经 NAT |
| **成本** | ALB 公网数据传输费 | 无额外费用（VPC Origin 免费） |
| **配置复杂度** | 低 | 中等（需配置安全组链） |

---

## 2. 前提条件

| 资源 | 说明 | 验证命令 |
|------|------|---------|
| VPC | `vpc-086e15047c7f68e87` | `aws ec2 describe-vpcs --vpc-ids vpc-086e15047c7f68e87 --query "Vpcs[0].State" --output text --region ap-northeast-1` |
| Private Subnet (至少 2 个) | 用于 VPC Origin ENI | `aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-086e15047c7f68e87" "Name=map-public-ip-on-launch,Values=false" --query "Subnets[].{Id:SubnetId,AZ:AvailabilityZone}" --output table --region ap-northeast-1` |
| Internal ALB | 已创建且健康检查通过 | `aws elbv2 describe-load-balancers --names unice-demo-alb --query "LoadBalancers[0].{Scheme:Scheme,State:State.Code,DNSName:DNSName}" --output table --region ap-northeast-1` |
| EC2 实例 | Express 应用运行中 | `aws elbv2 describe-target-health --target-group-arn YOUR_TG_ARN --query "TargetHealthDescriptions[0].TargetHealth.State" --output text --region ap-northeast-1` |
| CloudFront Distribution | 已创建 | `aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" --output text` |

---

## 3. 操作步骤

### 步骤 1: 创建 VPC Origin 安全组

VPC Origin ENI 需要一个专用安全组，控制 ENI 到 ALB 的出站流量：

**在 Console 中操作**：

1. 打开 [VPC Console → Security Groups](https://ap-northeast-1.console.aws.amazon.com/vpc/home?region=ap-northeast-1#SecurityGroups:)
2. 点击 **Create security group**

| 配置项 | 值 |
|-------|---|
| **Security group name** | `unice-demo-vpc-origin-sg` |
| **Description** | `Security group for CloudFront VPC Origin ENIs` |
| **VPC** | `vpc-086e15047c7f68e87` |

3. **Inbound rules**：不添加任何入站规则（VPC Origin ENI 只发送请求，不接收）
4. **Outbound rules**：删除默认的 "All traffic" 规则，添加：

| Type | Protocol | Port | Destination | Description |
|------|----------|------|-------------|-------------|
| Custom TCP | TCP | 80 | ALB 安全组 ID | Allow HTTP to Internal ALB |

5. 点击 **Create security group**

```bash
# CLI 创建安全组
VPC_ORIGIN_SG=$(aws ec2 create-security-group \
  --group-name "unice-demo-vpc-origin-sg" \
  --description "Security group for CloudFront VPC Origin ENIs" \
  --vpc-id vpc-086e15047c7f68e87 \
  --region ap-northeast-1 \
  --query "GroupId" --output text)

echo "VPC Origin SG: $VPC_ORIGIN_SG"

# 获取 ALB 安全组 ID
ALB_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=unice-demo-alb-sg" \
  --query "SecurityGroups[0].GroupId" --output text \
  --region ap-northeast-1)

# 删除默认出站规则
aws ec2 revoke-security-group-egress \
  --group-id $VPC_ORIGIN_SG \
  --protocol -1 --port -1 --cidr 0.0.0.0/0 \
  --region ap-northeast-1

# 添加出站规则：仅允许到 ALB SG 的 HTTP 80
aws ec2 authorize-security-group-egress \
  --group-id $VPC_ORIGIN_SG \
  --protocol tcp --port 80 \
  --source-group $ALB_SG \
  --region ap-northeast-1
```

### 步骤 2: 更新 ALB 安全组 — 允许 VPC Origin 入站

ALB 安全组需要添加一条入站规则，允许来自 VPC Origin 安全组的 HTTP 流量：

**在 Console 中操作**：

1. 打开 [VPC Console → Security Groups](https://ap-northeast-1.console.aws.amazon.com/vpc/home?region=ap-northeast-1#SecurityGroups:)
2. 找到 ALB 安全组（`unice-demo-alb-sg`），点击进入
3. 点击 **Inbound rules** → **Edit inbound rules**
4. 添加规则：

| Type | Protocol | Port | Source | Description |
|------|----------|------|--------|-------------|
| HTTP | TCP | 80 | VPC Origin 安全组 ID | Allow HTTP from CloudFront VPC Origin |

5. **删除**任何允许 `0.0.0.0/0` 入站的规则（如果存在）
6. 点击 **Save rules**

```bash
# CLI 更新 ALB 安全组入站规则
aws ec2 authorize-security-group-ingress \
  --group-id $ALB_SG \
  --protocol tcp --port 80 \
  --source-group $VPC_ORIGIN_SG \
  --region ap-northeast-1

echo "ALB SG updated: allows inbound from VPC Origin SG only"
```

> **关键设计点**：ALB 安全组的入站规则 **仅** 引用 VPC Origin 安全组 ID，不使用任何 CIDR 范围。这意味着只有绑定了 VPC Origin 安全组的 ENI 才能连接 ALB，其他任何来源（包括 VPC 内部的其他实例）都无法访问。

### 步骤 3: 在 Console 中创建 VPC Origin

1. 打开 [CloudFront Console](https://console.aws.amazon.com/cloudfront/)
2. 在左侧导航栏中，点击 **VPC origins** (在 Origin 分类下)
3. 点击 **Create VPC origin** 按钮
4. 填写以下信息：

| 配置项 | 值 | 说明 |
|-------|---|------|
| **Name** | `unice-demo-vpc-origin` | VPC Origin 名称 |
| **ARN** | 选择 Internal ALB 的 ARN | 从下拉列表选择 `unice-demo-alb` |

> CloudFront 会自动检测 ALB 所在的 VPC、子网和建议的安全组配置。

5. **VPC** 和 **Subnets** 会自动填充（从 ALB 配置推断）
6. **Security group**：选择步骤 1 创建的 `unice-demo-vpc-origin-sg`
7. 点击 **Create VPC origin**

```bash
# CLI 创建 VPC Origin
# 首先获取 Internal ALB ARN
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --names unice-demo-alb \
  --query "LoadBalancers[0].LoadBalancerArn" --output text \
  --region ap-northeast-1)

echo "ALB ARN: $ALB_ARN"

# 创建 VPC Origin
aws cloudfront create-vpc-origin \
  --vpc-origin-endpoint-config '{
    "Name": "unice-demo-vpc-origin",
    "Arn": "'$ALB_ARN'",
    "HTTPPort": 80,
    "HTTPSPort": 443,
    "OriginProtocolPolicy": "http-only",
    "OriginSslProtocols": {
      "Quantity": 1,
      "Items": ["TLSv1.2"]
    }
  }' \
  --region ap-northeast-1
```

> **等待 VPC Origin 部署**：创建后状态为 `Deploying`，通常需要 5-10 分钟变为 `Deployed`。在此期间 CloudFront 在你的 VPC 子网中创建 ENI。

```bash
# 检查 VPC Origin 状态
aws cloudfront list-vpc-origins \
  --query "VpcOriginList.Items[?Name=='unice-demo-vpc-origin'].{Id:Id,Status:Status}" \
  --output table
```

### 步骤 4: 将 VPC Origin 绑定到 Distribution

1. 回到 CloudFront Console，点击你的 Distribution（`unice.keithyu.cloud`）
2. 点击 **Origins** 选项卡
3. 点击 **Create origin**（或编辑已有的 ALB Origin）

| 配置项 | 值 | 说明 |
|-------|---|------|
| **Origin domain** | 选择 VPC Origin（`unice-demo-vpc-origin`） | 从下拉列表中选择 |
| **Protocol** | HTTP only | Internal ALB 使用 HTTP 80 |
| **HTTP port** | 80 | 默认 |
| **Origin path** | 留空 | 无需路径前缀 |
| **Name** | `unice-demo-alb-vpc-origin` | Origin 标识名 |
| **Connection attempts** | 3 | 连接失败重试次数 |
| **Connection timeout** | 10 | 连接超时秒数 |

4. 点击 **Create origin**（或 **Save changes**）

5. **更新 Cache Behaviors**：将所有指向 ALB 的 Behavior（`/api/*`、Default `*` 等）的 Origin 改为新的 VPC Origin

### 步骤 5: 等待部署完成

```bash
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
  --output text)

# 等待部署
aws cloudfront wait distribution-deployed --id $DIST_ID
echo "Distribution with VPC Origin deployed successfully"
```

---

## 4. 验证

### 验证 1: 通过 CloudFront 访问动态页面 — 应正常返回

```bash
# 健康检查端点
curl -s "https://unice.keithyu.cloud/api/health" | jq .

# 预期输出:
# {
#   "status": "ok",
#   "timestamp": "2026-04-14T...",
#   "traceId": "...",
#   "version": "1.0.0",
#   ...
# }
```

```bash
# Debug 端点 - 查看 CloudFront 注入的 Header
curl -s "https://unice.keithyu.cloud/api/debug" | jq '.headers'

# 应该能看到 CloudFront 注入的 header:
# "x-forwarded-for": "客户端IP, CloudFront Edge IP"
# "cloudfront-viewer-country": "XX"
# 等
```

### 验证 2: 直接访问 Internal ALB DNS — 应不可达

```bash
# 获取 Internal ALB DNS 名称
ALB_DNS=$(aws elbv2 describe-load-balancers \
  --names unice-demo-alb \
  --query "LoadBalancers[0].DNSName" --output text \
  --region ap-northeast-1)

echo "ALB DNS: $ALB_DNS"

# 尝试直接访问 Internal ALB（从外网）— 应超时或拒绝
curl -s --connect-timeout 5 "http://${ALB_DNS}/api/health" 2>&1 || \
  echo "Connection failed as expected - ALB is internal only"

# 预期: 连接超时。因为 Internal ALB 没有公网 IP，外部无法路由
```

### 验证 3: 查看 VPC Origin ENI

```bash
# 查看 CloudFront 在 VPC 中创建的 ENI
aws ec2 describe-network-interfaces \
  --filters "Name=group-id,Values=$VPC_ORIGIN_SG" \
  --query "NetworkInterfaces[].{Id:NetworkInterfaceId,AZ:AvailabilityZone,PrivateIp:PrivateIpAddress,Status:Status,Description:Description}" \
  --output table \
  --region ap-northeast-1

# 预期: 看到 1-2 个 ENI，描述中包含 "CloudFront VPC Origin"
```

### 验证 4: 确认安全组链式隔离

```bash
# 验证 ALB 安全组入站规则 — 应仅有 VPC Origin SG
aws ec2 describe-security-groups \
  --group-ids $ALB_SG \
  --query "SecurityGroups[0].IpPermissions[].{Port:FromPort,Source:UserIdGroupPairs[0].GroupId}" \
  --output table \
  --region ap-northeast-1

# 预期: Source = VPC Origin SG ID, Port = 80
```

```bash
# 验证 EC2 安全组入站规则 — 应仅有 ALB SG
EC2_SG=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=unice-demo-ec2-sg" \
  --query "SecurityGroups[0].GroupId" --output text \
  --region ap-northeast-1)

aws ec2 describe-security-groups \
  --group-ids $EC2_SG \
  --query "SecurityGroups[0].IpPermissions[].{Port:FromPort,Source:UserIdGroupPairs[0].GroupId}" \
  --output table \
  --region ap-northeast-1

# 预期: Source = ALB SG ID, Port = 3000
```

### 验证 5: 端到端性能测试

```bash
# 测试响应时间（含 DNS 解析、TLS 握手、首字节时间）
curl -s -o /dev/null -w \
  "DNS: %{time_namelookup}s\nTCP: %{time_connect}s\nTLS: %{time_appconnect}s\nTTFB: %{time_starttransfer}s\nTotal: %{time_total}s\n" \
  "https://unice.keithyu.cloud/api/health"

# VPC Origin 不会增加额外延迟，因为走 AWS 内部网络
# 典型 TTFB (首字节时间): 50-200ms（取决于 PoP 到东京的距离）
```

---

## 5. 安全组链式信任详解

本平台的安全组设计遵循 **最小权限原则**，形成严格的链式信任关系：

```
VPC Origin SG ──出站 port 80──→ ALB SG ──出站 port 3000──→ EC2 SG ──出站 all──→ 外部
     (无入站)                    (入站仅 VPC Origin)        (入站仅 ALB)
```

| 安全组 | 入站规则 | 出站规则 | 设计意图 |
|-------|---------|---------|---------|
| `vpc-origin-sg` | 无 | 仅 ALB SG port 80 | ENI 只向 ALB 发送流量 |
| `alb-sg` | 仅 VPC Origin SG port 80 | 仅 EC2 SG port 3000 | ALB 只接受 CF 流量，只转发给 EC2 |
| `ec2-sg` | 仅 ALB SG port 3000 | All（NAT/VPC Endpoint） | EC2 只接受 ALB 转发，需外联安装依赖 |

> **安全价值**：即使攻击者通过某种方式获取了 VPC 内一台实例的权限，也无法直接访问 ALB 或 EC2（因为安全组是基于安全组 ID 引用的，不是 IP 范围）。

---

## 6. 常见问题排查

### 问题 1: VPC Origin 状态一直是 Deploying

```bash
# 检查 VPC Origin 详细状态
aws cloudfront list-vpc-origins --output json | jq '.VpcOriginList.Items[] | select(.Name=="unice-demo-vpc-origin")'
```

**常见原因**：
- 指定的子网没有足够的可用 IP 地址
- 安全组规则配置错误导致健康检查失败
- IAM 权限不足（CloudFront 需要 `ec2:CreateNetworkInterface` 等权限，但这是服务级权限，通常不需要手动配置）

### 问题 2: 通过 CloudFront 返回 502/504

```bash
# 检查 ALB Target Group 健康状态
TG_ARN=$(aws elbv2 describe-target-groups \
  --names unice-demo-tg \
  --query "TargetGroups[0].TargetGroupArn" --output text \
  --region ap-northeast-1)

aws elbv2 describe-target-health \
  --target-group-arn $TG_ARN \
  --output table \
  --region ap-northeast-1
```

**常见原因**：
- EC2 实例不健康（Express 未启动）
- ALB 安全组出站规则未允许到 EC2 SG 的 port 3000
- VPC Origin 安全组出站规则未允许到 ALB SG 的 port 80

### 问题 3: 如何在不影响生产的情况下测试 VPC Origin

**方法 A: 使用 Cache Behavior**
- 创建一个测试路径（如 `/test-vpc/*`）的 Behavior，指向 VPC Origin
- 其他路径仍指向原来的 Public ALB Origin

**方法 B: 使用 Continuous Deployment**
- 参见下一篇文档（11-cloudfront-continuous-deployment.md），通过 Staging Distribution 测试

---

## 7. CLI 快速参考

```bash
# 列出所有 VPC Origin
aws cloudfront list-vpc-origins \
  --query "VpcOriginList.Items[].{Id:Id,Name:Name,Status:Status,Arn:VpcOriginEndpointConfig.Arn}" \
  --output table

# 查看 VPC Origin 详情
aws cloudfront get-vpc-origin --id YOUR_VPC_ORIGIN_ID

# 查看 VPC Origin 创建的 ENI
aws ec2 describe-network-interfaces \
  --filters "Name=description,Values=*CloudFront*" \
  --query "NetworkInterfaces[].{Id:NetworkInterfaceId,AZ:AvailabilityZone,IP:PrivateIpAddress,SG:Groups[0].GroupId}" \
  --output table --region ap-northeast-1

# 删除 VPC Origin（先从 Distribution 解绑）
aws cloudfront delete-vpc-origin --id YOUR_VPC_ORIGIN_ID --if-match YOUR_ETAG
```
