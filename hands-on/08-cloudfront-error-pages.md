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
