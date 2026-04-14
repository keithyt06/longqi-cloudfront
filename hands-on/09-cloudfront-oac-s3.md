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
