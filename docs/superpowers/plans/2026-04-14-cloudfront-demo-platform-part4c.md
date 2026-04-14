# CloudFront 全功能演示平台 - 实施计划 Part 4C

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 编写 3 篇高级功能 hands-on 文档（09-11），覆盖 OAC 源站保护、VPC Origin 全内网架构、Continuous Deployment 灰度发布。每篇包含完整的 AWS Console 操作步骤、CLI 验证命令和原理说明，可直接交付客户使用。

**Architecture:** CloudFront → VPC Origin → Internal ALB → EC2 Express，S3 通过 OAC 保护，Staging Distribution 实现灰度发布。

**Tech Stack:** AWS CloudFront, S3 OAC, VPC Origin, Continuous Deployment, Internal ALB

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

**设计规格参考:** Section 3（网络架构 / VPC Origin / 安全组）、Section 9（Continuous Deployment）

---

## 文件结构总览 (Part 4C)

```
hands-on/
├── 09-cloudfront-oac-s3.md              # OAC 源站保护：OAC vs OAI、创建 OAC、S3 Bucket Policy、验证
├── 10-cloudfront-vpc-origin.md          # VPC Origin 全内网架构：ENI 机制、创建配置、安全组、验证
└── 11-cloudfront-continuous-deployment.md  # 灰度发布：Staging Distribution、CD Policy、测试与回滚
```

---

## Phase 4C: Hands-on 文档 09-11 (Task 18)

### Task 18: 高级功能文档

编写 3 篇完整的 hands-on 实操文档，涵盖 CloudFront 的三个高级功能。每篇文档包含：功能原理与架构说明、AWS Console 逐步操作、CLI/curl 验证命令、常见问题排查。文档面向具备基础 AWS 经验的技术人员，可作为客户自助学习材料或 Workshop 教材。

---

### Step 18.1: 创建 `hands-on/09-cloudfront-oac-s3.md`

- [ ] 创建文件 `hands-on/09-cloudfront-oac-s3.md`，完整 OAC 源站保护文档

```markdown
# 09 - CloudFront Origin Access Control (OAC) 保护 S3 源站

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 30 分钟 | **难度**: 中级 | **前置要求**: 已完成 01（Distribution 创建）

---

## 1. 功能概述

### 1.1 什么是 OAC

Origin Access Control (OAC) 是 AWS 在 2022 年推出的 S3 源站保护机制，用于替代旧版的 Origin Access Identity (OAI)。它确保 S3 桶中的内容 **只能通过指定的 CloudFront Distribution 访问**，直接访问 S3 URL 将返回 403 Forbidden。

**核心价值**：防止用户绕过 CloudFront 直接访问 S3，确保所有请求都经过 CDN 的缓存加速、WAF 安全防护和访问日志记录。

### 1.2 OAC vs OAI 对比

| 维度 | OAI (旧版) | OAC (推荐) |
|------|-----------|-----------|
| **发布时间** | 2008 年 | 2022 年 |
| **SSE-KMS 加密** | 不支持 | 支持（可用 KMS 密钥加密 S3 对象） |
| **S3 区域支持** | 仅部分区域 | 所有 AWS 区域（含 2022 年后新增区域） |
| **动态请求** | 仅 GET/HEAD | 支持 PUT/POST/PATCH/DELETE（可用于 S3 上传） |
| **SigV4 签名** | 不支持 | 原生 SigV4 签名 |
| **IAM 策略粒度** | 基于 OAI 身份 | 基于 Distribution ARN（更精确、更安全） |
| **AWS 建议** | 迁移到 OAC | 新项目一律使用 OAC |

**关键区别**：OAI 使用一个特殊的 CloudFront 身份（类似虚拟用户），而 OAC 直接使用 CloudFront Distribution 的 ARN 作为授权凭据，粒度更细、管理更简单。

### 1.3 工作原理

```
用户请求 → CloudFront Edge
                │
                ├─ CloudFront 用 OAC 签名算法（SigV4）签署请求
                │
                ├─ 签名后的请求发送到 S3
                │
                └─ S3 检查 Bucket Policy:
                     ├─ Principal: cloudfront.amazonaws.com ✓
                     ├─ Condition: AWS:SourceArn = 指定 Distribution ARN ✓
                     └─ 放行 → 返回内容

直接访问 S3 URL → S3 检查 Bucket Policy → 无有效签名 → 403 Forbidden
```

---

## 2. 前提条件

在开始之前，请确认以下资源已就绪：

| 资源 | 说明 | 验证命令 |
|------|------|---------|
| CloudFront Distribution | 已创建并部署完成 | `aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].{Id:Id,Status:Status}" --output table` |
| S3 桶 | 静态资源桶已创建 | `aws s3 ls s3://unice-static-keithyu-tokyo/ --region ap-northeast-1` |
| S3 公共访问已阻止 | Block Public Access 已全部开启 | `aws s3api get-public-access-block --bucket unice-static-keithyu-tokyo --region ap-northeast-1` |

---

## 3. 操作步骤

### 步骤 1: 上传测试文件到 S3

首先上传一个测试文件，用于后续验证 OAC 是否生效：

```bash
# 创建测试文件
echo '<html><body><h1>OAC Protected Content</h1><p>This file is only accessible via CloudFront.</p></body></html>' > /tmp/oac-test.html

# 上传到 S3
aws s3 cp /tmp/oac-test.html s3://unice-static-keithyu-tokyo/static/oac-test.html \
  --content-type "text/html" \
  --region ap-northeast-1

# 确认上传成功
aws s3 ls s3://unice-static-keithyu-tokyo/static/oac-test.html --region ap-northeast-1
```

### 步骤 2: 验证直接访问 S3 返回 403

在配置 OAC 之前（假设 S3 已阻止公共访问），直接访问 S3 URL 应返回 403：

```bash
# 获取 S3 区域域名
S3_DOMAIN="unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com"

# 直接访问 S3 — 应返回 403 Forbidden
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://${S3_DOMAIN}/static/oac-test.html"

# 预期输出: HTTP Status: 403
```

### 步骤 3: 在 Console 中创建 OAC

1. 打开 [CloudFront Console](https://console.aws.amazon.com/cloudfront/)
2. 在左侧导航栏中，点击 **Origin access** (在 Security 分类下)
3. 点击 **Create control setting** 按钮
4. 填写以下信息：

| 配置项 | 值 | 说明 |
|-------|---|------|
| **Name** | `unice-demo-oac` | OAC 名称，描述性命名 |
| **Description** | `OAC for unice-demo S3 static assets` | 可选描述 |
| **Signing protocol** | `Sigv4` | 推荐使用 SigV4（默认） |
| **Signing behavior** | `Sign requests (recommended)` | CloudFront 对所有请求签名 |
| **Origin type** | `S3` | 源站类型选择 S3 |

5. 点击 **Create**

> **Signing behavior 选项说明**：
> - **Sign requests (recommended)**：CloudFront 始终对发往 S3 的请求进行签名，S3 通过 Bucket Policy 验证
> - **Do not sign requests**：不签名，S3 必须通过其他方式认证（少见）
> - **Do not override authorization header**：如果请求自带 Authorization header 则不覆盖（高级用法）

### 步骤 4: 将 OAC 绑定到 S3 Origin

1. 回到 CloudFront Console，点击你的 Distribution（`unice.keithyu.cloud`）
2. 点击 **Origins** 选项卡
3. 找到 S3 Origin（域名为 `unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com`），点击 **Edit**
4. 在 **Origin access** 部分：
   - 选择 **Origin access control settings (recommended)**
   - 在下拉菜单中选择刚创建的 `unice-demo-oac`

5. 如果之前有选择 OAI，取消勾选
6. 点击 **Save changes**

> **重要提示**：保存后 Console 顶部会出现蓝色横幅，提示你需要更新 S3 Bucket Policy。点击 **Copy policy** 按钮复制策略，下一步使用。

### 步骤 5: 配置 S3 Bucket Policy

CloudFront Console 会自动生成推荐的 Bucket Policy。你也可以手动配置：

1. 打开 [S3 Console](https://console.aws.amazon.com/s3/)
2. 点击桶 `unice-static-keithyu-tokyo`
3. 点击 **Permissions** 选项卡
4. 在 **Bucket policy** 部分点击 **Edit**
5. 粘贴以下策略：

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
                    "AWS:SourceArn": "arn:aws:cloudfront::434465421667:distribution/YOUR_DISTRIBUTION_ID"
                }
            }
        }
    ]
}
```

> **替换 `YOUR_DISTRIBUTION_ID`**：将上面的 Distribution ID 替换为你的实际值。可通过以下命令获取：
> ```bash
> aws cloudfront list-distributions \
>   --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
>   --output text
> ```

6. 点击 **Save changes**

**策略解读**：
- `Principal: cloudfront.amazonaws.com`：只允许 CloudFront 服务访问
- `Condition: AWS:SourceArn`：进一步限制到 **指定的 Distribution**。即使同一 AWS 账号下有其他 CloudFront Distribution，也无法访问此桶
- `Action: s3:GetObject`：仅允许读取对象，不允许列出桶内容或写入

### 步骤 6: 等待 Distribution 部署完成

OAC 配置变更需要 CloudFront 全球传播，通常需要 3-5 分钟：

```bash
# 获取 Distribution ID
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
  --output text)

# 检查部署状态（等待变为 Deployed）
aws cloudfront get-distribution --id $DIST_ID \
  --query "Distribution.Status" --output text

# 也可以用 wait 命令阻塞等待
aws cloudfront wait distribution-deployed --id $DIST_ID
echo "Distribution deployed successfully"
```

---

## 4. 验证

### 验证 1: 通过 CloudFront 访问 — 应返回 200

```bash
# 通过 CloudFront 域名访问
curl -s -o /dev/null -w "HTTP Status: %{http_code}\nContent-Type: %{content_type}\n" \
  "https://unice.keithyu.cloud/static/oac-test.html"

# 预期输出:
# HTTP Status: 200
# Content-Type: text/html
```

```bash
# 查看完整响应内容
curl -s "https://unice.keithyu.cloud/static/oac-test.html"

# 预期输出:
# <html><body><h1>OAC Protected Content</h1><p>This file is only accessible via CloudFront.</p></body></html>
```

### 验证 2: 直接访问 S3 URL — 应返回 403

```bash
# 直接访问 S3 URL
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com/static/oac-test.html"

# 预期输出: HTTP Status: 403
```

```bash
# 查看 403 的具体错误信息
curl -s "https://unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com/static/oac-test.html"

# 预期输出（XML 格式）:
# <?xml version="1.0" encoding="UTF-8"?>
# <Error><Code>AccessDenied</Code><Message>Access Denied</Message>...</Error>
```

### 验证 3: 检查 CloudFront 响应头

```bash
# 查看 CloudFront 响应头中的缓存信息
curl -sI "https://unice.keithyu.cloud/static/oac-test.html" | grep -i -E "x-cache|x-amz|age|via"

# 预期输出:
# X-Cache: Miss from cloudfront      (首次请求，缓存未命中)
# Via: 1.1 xxxx.cloudfront.net (CloudFront)
# X-Amz-Cf-Pop: NRT51-C1            (东京 PoP 节点)
```

```bash
# 再次请求，验证缓存命中
curl -sI "https://unice.keithyu.cloud/static/oac-test.html" | grep -i "x-cache"

# 预期输出:
# X-Cache: Hit from cloudfront       (缓存命中)
```

### 验证 4: 确认其他 Distribution 无法访问

如果你的账号下有其他 CloudFront Distribution，可以验证它们无法通过 OAC 访问此桶：

```bash
# 通过 AWS CLI 直接尝试从其他身份获取对象（模拟非授权访问）
# 预期: AccessDenied
aws s3api get-object \
  --bucket unice-static-keithyu-tokyo \
  --key static/oac-test.html \
  /tmp/test-download.html \
  --region ap-northeast-1 2>&1 || echo "Access denied as expected"
```

> 注意：如果你的 IAM 用户/角色有 `s3:GetObject` 权限，CLI 仍然可以访问。OAC 的 Bucket Policy 是 **额外** 的 Allow 语句，不会阻止 IAM 权限。要完全限制只能通过 CloudFront 访问，需要添加 Deny 语句。

---

## 5. 高级：添加 Deny 策略（可选）

如果需要 **强制** 所有访问都必须通过 CloudFront（包括禁止 IAM 用户直接访问），可以添加 Deny 语句：

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
                    "AWS:SourceArn": "arn:aws:cloudfront::434465421667:distribution/YOUR_DISTRIBUTION_ID"
                }
            }
        },
        {
            "Sid": "DenyNonCloudFrontAccess",
            "Effect": "Deny",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::unice-static-keithyu-tokyo/*",
            "Condition": {
                "StringNotEquals": {
                    "AWS:SourceArn": "arn:aws:cloudfront::434465421667:distribution/YOUR_DISTRIBUTION_ID"
                }
            }
        }
    ]
}
```

> **警告**：添加 Deny 语句后，你自己的 IAM 用户也无法直接下载 S3 对象。仅在明确需要时启用。

---

## 6. 从 OAI 迁移到 OAC

如果你的 Distribution 目前使用 OAI，可以按以下步骤无缝迁移：

1. **创建 OAC**（步骤 3）
2. **更新 S3 Bucket Policy**：同时保留 OAI 和 OAC 的 Allow 语句（过渡期）
3. **更新 CloudFront Origin**：将 Origin access 从 OAI 切换为 OAC
4. **等待部署完成**
5. **验证** 通过 CloudFront 访问正常
6. **清理**：从 Bucket Policy 中移除 OAI 语句，删除不再使用的 OAI

---

## 7. 常见问题排查

### 问题 1: 通过 CloudFront 访问仍然返回 403

**排查步骤**：

```bash
# 检查 Bucket Policy 是否正确
aws s3api get-bucket-policy --bucket unice-static-keithyu-tokyo \
  --region ap-northeast-1 --output text | jq .

# 确认 Distribution ARN 是否匹配
aws cloudfront get-distribution --id $DIST_ID \
  --query "Distribution.ARN" --output text
```

**常见原因**：
- Bucket Policy 中的 Distribution ARN 不匹配（注意是 ARN，不是 Distribution ID）
- OAC 的 Signing behavior 选择了 "Do not sign requests"
- Distribution 尚未部署完成（Status 不是 Deployed）

### 问题 2: S3 桶在 2022 年后新增的区域

如果 S3 桶位于 2022 年后新增的 AWS 区域（如 ap-south-2, eu-south-2 等），**必须** 使用 OAC，OAI 不支持这些区域。

### 问题 3: 需要同时保护多个路径

OAC 是 Origin 级别的配置，只要 Bucket Policy 的 Resource 使用通配符（`/*`），就会保护桶内所有对象。如果需要按路径精细控制，可以在 Bucket Policy 中使用多条 Statement，为不同前缀设置不同权限。

---

## 8. CLI 快速参考

```bash
# 列出所有 OAC
aws cloudfront list-origin-access-controls \
  --query "OriginAccessControlList.Items[].{Id:Id,Name:Name,SigningProtocol:SigningProtocol}" \
  --output table

# 查看 OAC 详情
aws cloudfront get-origin-access-control --id YOUR_OAC_ID

# 查看 Distribution 的 Origin 配置
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.Origins.Items[?DomainName=='unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com']" \
  --output json | jq .

# 查看当前 Bucket Policy
aws s3api get-bucket-policy --bucket unice-static-keithyu-tokyo \
  --region ap-northeast-1 --output text | jq .
```
```

---

### Step 18.2: 创建 `hands-on/10-cloudfront-vpc-origin.md`

- [ ] 创建文件 `hands-on/10-cloudfront-vpc-origin.md`，完整 VPC Origin 文档

```markdown
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
```

---

### Step 18.3: 创建 `hands-on/11-cloudfront-continuous-deployment.md`

- [ ] 创建文件 `hands-on/11-cloudfront-continuous-deployment.md`，完整灰度发布文档

```markdown
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
```
