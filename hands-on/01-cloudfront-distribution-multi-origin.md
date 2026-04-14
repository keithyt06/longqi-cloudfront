# 01 - 创建 CloudFront Distribution：多源路由架构

> **目标**: 创建一个 CloudFront Distribution，配置 S3 (OAC) 和 ALB (VPC Origin) 双源，通过多条 Cache Behavior 实现按路径路由。
>
> **预计时间**: 30-40 分钟
>
> **前提条件**:
> - 已有 S3 桶（存放静态资源）：`unice-static-keithyu-tokyo`
> - 已有 Internal ALB（后端 Express 应用）
> - 已有 ACM 证书（us-east-1，覆盖 `*.keithyu.cloud`）
> - 已有 Route53 托管区域 `keithyu.cloud`

---

## 架构概览

```
用户请求 → CloudFront (unice.keithyu.cloud)
              ├── /static/*    → S3 Origin (OAC)     [静态资源: CSS/JS/字体]
              ├── /images/*    → S3 Origin (OAC)     [商品图片]
              ├── /api/*       → ALB Origin (VPC)    [动态 API]
              └── Default (*)  → ALB Origin (VPC)    [SSR 页面]
```

---

## 步骤 1: 创建 Origin Access Control (OAC)

OAC 用于授权 CloudFront 访问私有 S3 桶，替代已废弃的 OAI。

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Security** → **Origin access**
- [ ] 点击 **Create control setting**
- [ ] 填写配置：

| 参数 | 值 |
|------|-----|
| Name | `unice-s3-oac` |
| Description | `OAC for unice static S3 bucket` |
| Signing behavior | **Sign requests (recommended)** |
| Origin type | **S3** |

- [ ] 点击 **Create**

> **说明**: OAC 会让 CloudFront 对每个发往 S3 的请求进行 SigV4 签名。S3 桶策略通过验证签名来确认请求确实来自指定的 CloudFront Distribution。

---

## 步骤 2: 创建 CloudFront Distribution

- [ ] 打开 **CloudFront Console** → 点击 **Create distribution**

### 2.1 配置 S3 Origin（默认 Origin）

| 参数 | 值 |
|------|-----|
| Origin domain | `unice-static-keithyu-tokyo.s3.ap-northeast-1.amazonaws.com`（从下拉列表选择） |
| Origin name | `S3-unice-static` |
| Origin access | **Origin access control settings (recommended)** |
| Origin access control | 选择 `unice-s3-oac` |
| Enable Origin Shield | No |

- [ ] 配置完成后，CloudFront 会提示需要更新 S3 Bucket Policy —— **先记下提示的策略内容，稍后配置**

### 2.2 配置 Default Cache Behavior

| 参数 | 值 |
|------|-----|
| Path pattern | `Default (*)` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** |
| Cache key and origin requests | **Cache policy and origin request policy (recommended)** |
| Cache policy | `CachingDisabled`（临时设置，后续步骤更改） |
| Origin request policy | `AllViewer` |
| Response headers policy | 无 |

### 2.3 配置 Settings

| 参数 | 值 |
|------|-----|
| Price class | **Use North America, Europe, Asia, Middle East, and Africa** (PriceClass_200) |
| AWS WAF web ACL | 暂不关联（文档 04 配置） |
| Alternate domain name (CNAME) | `unice.keithyu.cloud` |
| Custom SSL certificate | 选择 `*.keithyu.cloud`（us-east-1 证书） |
| Security policy | **TLSv1.2_2021 (recommended)** |
| Supported HTTP versions | **HTTP/2** |
| Default root object | `index.html` |
| Standard logging | Off（可后续开启） |
| IPv6 | On |

- [ ] 点击 **Create distribution**
- [ ] **记录 Distribution ID**（如 `E1XXXXXXXXXX`）和 **Distribution Domain**（如 `dxxxxxxxxxx.cloudfront.net`）

---

## 步骤 3: 更新 S3 Bucket Policy

- [ ] 打开 **S3 Console** → 选择桶 `unice-static-keithyu-tokyo` → **Permissions** 标签 → **Bucket policy** → **Edit**
- [ ] 粘贴以下策略（将 `DISTRIBUTION_ARN` 替换为实际值）：

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
                    "AWS:SourceArn": "arn:aws:cloudfront::434465421667:distribution/DISTRIBUTION_ID"
                }
            }
        }
    ]
}
```

- [ ] 点击 **Save changes**

---

## 步骤 4: 添加 ALB Origin (VPC Origin)

VPC Origin 让 CloudFront 通过 AWS 内部网络直接连接 Internal ALB，无需 ALB 暴露公网。

- [ ] 打开 **CloudFront Console** → 选择刚创建的 Distribution → **Origins** 标签 → **Create origin**

| 参数 | 值 |
|------|-----|
| Origin domain | 选择 Internal ALB 的 DNS 名称（如 `internal-unice-demo-alb-xxxxxxxxx.ap-northeast-1.elb.amazonaws.com`） |
| Origin name | `ALB-unice-internal` |
| Protocol | **HTTP only** |
| HTTP port | `80` |
| Enable Origin Shield | No |

> **VPC Origin 配置**：当选择 Internal ALB 作为 Origin 时，CloudFront 会自动检测到这是一个内网资源，并提示启用 VPC Origin。

- [ ] 在 VPC Origin 配置部分：

| 参数 | 值 |
|------|-----|
| VPC Origin | **Create new VPC origin** |
| VPC | 选择现有 VPC |
| Security group | 选择 `unice-demo-vpc-origin-sg` |

- [ ] 点击 **Create origin**
- [ ] 等待 VPC Origin 状态变为 **Deployed**（约 3-5 分钟）

---

## 步骤 5: 配置多条 Cache Behavior

创建 4 条 Behavior，按路径将请求路由到不同 Origin。

### 5.1 创建 `/static/*` Behavior

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/static/*` |
| Origin and origin groups | `S3-unice-static` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD** |
| Cache policy | `CachingOptimized`（AWS 托管，TTL 86400s） |
| Origin request policy | 无 |

- [ ] 点击 **Create behavior**

### 5.2 创建 `/images/*` Behavior

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/images/*` |
| Origin and origin groups | `S3-unice-static` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD** |
| Cache policy | `CachingOptimized` |
| Origin request policy | 无 |

- [ ] 点击 **Create behavior**

### 5.3 创建 `/api/products*` Behavior

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/api/products*` |
| Origin and origin groups | `ALB-unice-internal` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS** |
| Cache policy | 自定义 `ProductCache`（文档 02 创建后回填，暂用 `CachingDisabled`） |
| Origin request policy | `AllViewer` |

- [ ] 点击 **Create behavior**

### 5.4 创建 `/api/*` Behavior（购物车/用户/订单/调试）

- [ ] **Behaviors** 标签 → **Create behavior**

| 参数 | 值 |
|------|-----|
| Path pattern | `/api/*` |
| Origin and origin groups | `ALB-unice-internal` |
| Compress objects automatically | **Yes** |
| Viewer protocol policy | **Redirect HTTP to HTTPS** |
| Allowed HTTP methods | **GET, HEAD, OPTIONS, PUT, POST, PATCH, DELETE** |
| Cache policy | `CachingDisabled`（AWS 托管） |
| Origin request policy | `AllViewer` |

- [ ] 点击 **Create behavior**

> **Behavior 优先级说明**: CloudFront 按从上到下的顺序匹配 Path Pattern。`/api/products*` 放在 `/api/*` 前面，确保商品 API 命中专属缓存策略，其余 API 走 CachingDisabled。Default (`*`) 在最后兜底。

### 5.5 调整 Default (*) Behavior

- [ ] 选择 **Default (*)** → **Edit**
- [ ] 修改 Origin 为 `ALB-unice-internal`
- [ ] Cache policy 暂设为 `CachingDisabled`（文档 02 创建 PageCache 后回填）
- [ ] Origin request policy 设为 `AllViewer`
- [ ] 点击 **Save changes**

---

## 步骤 6: 配置 Route53 DNS 记录

- [ ] 打开 **Route53 Console** → **Hosted zones** → `keithyu.cloud`
- [ ] 点击 **Create record**

| 参数 | 值 |
|------|-----|
| Record name | `unice` |
| Record type | **A** |
| Alias | **Yes** |
| Route traffic to | **Alias to CloudFront distribution** |
| Distribution | 选择刚创建的 Distribution |
| Routing policy | **Simple routing** |

- [ ] 点击 **Create records**

---

## 步骤 7: 验证

等待 Distribution 状态变为 **Deployed**（约 5-10 分钟），然后验证各路径：

### 7.1 验证 S3 Origin（静态资源）

先上传一个测试文件到 S3：

```bash
# 上传测试静态文件
echo '<h1>Hello from S3</h1>' > /tmp/test.html
aws s3 cp /tmp/test.html s3://unice-static-keithyu-tokyo/static/test.html \
  --region ap-northeast-1

# 验证通过 CloudFront 访问 S3 内容
curl -sI https://unice.keithyu.cloud/static/test.html
```

- [ ] 确认返回 `HTTP/2 200`
- [ ] 确认 `x-cache` header 为 `Miss from cloudfront`（首次访问）或 `Hit from cloudfront`（二次访问）

### 7.2 验证 ALB Origin（动态 API）

```bash
# 验证健康检查端点
curl -s https://unice.keithyu.cloud/api/health | jq .

# 验证 debug 端点（查看 CloudFront 注入的 headers）
curl -s https://unice.keithyu.cloud/api/debug | jq .headers
```

- [ ] 确认 `/api/health` 返回 `{"status":"ok",...}`
- [ ] 确认 `/api/debug` 中包含 `x-forwarded-for`、`x-forwarded-proto: https` 等 CloudFront 注入的 header

### 7.3 验证路径路由

```bash
# 测试默认路径（SSR 页面，走 ALB）
curl -sI https://unice.keithyu.cloud/

# 测试图片路径（走 S3）
echo 'test-image' > /tmp/test.jpg
aws s3 cp /tmp/test.jpg s3://unice-static-keithyu-tokyo/images/test.jpg \
  --region ap-northeast-1
curl -sI https://unice.keithyu.cloud/images/test.jpg
```

- [ ] 确认不同路径命中不同 Origin（通过 `x-cache` 和 `server` header 区分）

---

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| 403 AccessDenied 访问 S3 内容 | S3 Bucket Policy 未配置或 Distribution ARN 错误 | 检查 Bucket Policy 中的 `AWS:SourceArn` 是否匹配 Distribution ARN |
| 502 Bad Gateway 访问 API 路径 | VPC Origin 未就绪或安全组不通 | 确认 VPC Origin 状态为 Deployed；确认 vpc-origin-sg 出站允许 80 到 alb-sg |
| DNS 不解析 | Route53 记录未生效 | `dig unice.keithyu.cloud` 检查解析，CNAME 传播最多需要 60 秒 |
| HTTPS 证书错误 | ACM 证书不在 us-east-1 或未覆盖该域名 | CloudFront 只能使用 us-east-1 的证书，确认证书包含 `*.keithyu.cloud` |
