# 03 - CloudFront Functions：边缘计算实战

> **目标**: 创建并部署 3 个 CloudFront Functions（URL 重写、A/B 测试分流、地理位置重定向），理解边缘计算的使用场景和限制。
>
> **预计时间**: 30-40 分钟
>
> **前提条件**:
> - 已完成文档 01（Distribution 已创建并部署）

---

## CloudFront Functions 简介

CloudFront Functions 是运行在 CloudFront 边缘节点的轻量级 JavaScript 运行时：

| 特性 | CloudFront Functions | Lambda@Edge |
|------|---------------------|-------------|
| 执行延迟 | < 1ms | 5-50ms |
| 最大代码量 | 10 KB | 50 MB |
| 最大执行时间 | 2ms | 5s (Viewer) / 30s (Origin) |
| 网络访问 | 不支持 | 支持 |
| 触发阶段 | Viewer Request / Viewer Response | 全部 4 个阶段 |
| 费用 | $0.10 / 百万次 | $0.60 / 百万次 |

**适用场景**：URL 重写、Header 操作、Cookie 读写、简单重定向、请求校验。

---

## Function 1: URL 重写 (cf-url-rewrite)

### 功能说明

将用户友好的 URL（如 `/products/123`）重写为应用内部路由（如 `/api/products/123`），使 CloudFront 的 Behavior 路径匹配与前端 URL 解耦。

### 步骤 1.1: 创建 Function

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Functions** → **Create function**

| 参数 | 值 |
|------|-----|
| Name | `cf-url-rewrite` |
| Description | `Rewrite friendly URLs to internal API routes` |
| Runtime | **cloudfront-js-2.0** |

- [ ] 点击 **Create function**

### 步骤 1.2: 编写 Function 代码

- [ ] 在 **Build** 标签页中，替换默认代码为：

```javascript
function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // 路由重写规则
    var rewrites = [
        // /products/123 → /api/products/123
        { pattern: /^\/products\/(.+)$/, target: '/api/products/$1' },
        // /products → /api/products
        { pattern: /^\/products\/?$/, target: '/api/products' },
        // /cart → /api/cart
        { pattern: /^\/cart\/?$/, target: '/api/cart' },
        // /orders → /api/orders
        { pattern: /^\/orders\/?$/, target: '/api/orders' },
    ];

    for (var i = 0; i < rewrites.length; i++) {
        var match = uri.match(rewrites[i].pattern);
        if (match) {
            // 执行替换（支持 $1 捕获组）
            request.uri = rewrites[i].target.replace('$1', match[1] || '');
            break;
        }
    }

    return request;
}
```

- [ ] 点击 **Save changes**

### 步骤 1.3: 测试 Function

- [ ] 切换到 **Test** 标签页
- [ ] 配置测试事件：

| 参数 | 值 |
|------|-----|
| Event type | **Viewer Request** |
| Stage | **Development** |
| URL path | `/products/123` |
| HTTP method | `GET` |

- [ ] 点击 **Test function**
- [ ] 确认输出中 URI 已变为 `/api/products/123`

再测试其他路径：

| 输入 URI | 期望输出 URI |
|----------|-------------|
| `/products/123` | `/api/products/123` |
| `/products` | `/api/products` |
| `/cart` | `/api/cart` |
| `/static/style.css` | `/static/style.css`（不匹配，保持不变） |

### 步骤 1.4: 发布 Function

- [ ] 切换到 **Publish** 标签页 → 点击 **Publish function**

### 步骤 1.5: 关联到 Behavior

- [ ] 在 **Publish** 标签页下方 **Associated distributions** 区域 → **Add association**

| 参数 | 值 |
|------|-----|
| Distribution | 选择 `unice.keithyu.cloud` 对应的 Distribution |
| Event type | **Viewer Request** |
| Cache behavior | **Default (*)** |

- [ ] 点击 **Add association**

---

## Function 2: A/B 测试分流 (cf-ab-test)

### 功能说明

无需修改后端代码即可实现 A/B 测试。通过 Cookie 持久化用户的分组（A 或 B），确保同一用户始终看到同一版本。

### 步骤 2.1: 创建 Function

- [ ] **Functions** → **Create function**

| 参数 | 值 |
|------|-----|
| Name | `cf-ab-test` |
| Description | `A/B test traffic splitting via cookie` |
| Runtime | **cloudfront-js-2.0** |

### 步骤 2.2: 编写 Function 代码

- [ ] 替换默认代码为：

```javascript
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var cookies = request.cookies;

    // 检查是否已有 A/B 分组 cookie
    var abGroup = '';
    if (cookies['x-ab-group']) {
        abGroup = cookies['x-ab-group'].value;
    }

    // 如果没有分组，随机分配
    if (abGroup !== 'A' && abGroup !== 'B') {
        // 使用简单的伪随机：基于时间戳的最后一位奇偶判断
        // CloudFront Functions 不支持 Math.random()
        var timestamp = Date.now();
        abGroup = (timestamp % 2 === 0) ? 'A' : 'B';

        // 设置 cookie（通过在 request 中添加 cookie header 传给 Origin）
        // 并通过 response cookie 持久化到浏览器
        request.cookies['x-ab-group'] = { value: abGroup };
    }

    // 添加自定义 header 传递给 Origin（后端可据此返回不同内容）
    headers['x-ab-group'] = { value: abGroup };

    return request;
}
```

- [ ] 点击 **Save changes**

### 步骤 2.3: 测试 Function

- [ ] **Test** 标签页，Event type: **Viewer Request**

**测试场景 1 - 无 Cookie（新用户）**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Cookies | （空） |

- [ ] 确认输出包含 `x-ab-group` header，值为 `A` 或 `B`

**测试场景 2 - 有 Cookie（回访用户）**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Cookies | `x-ab-group=A` |

- [ ] 确认输出保持 `x-ab-group: A`（沿用已有分组）

### 步骤 2.4: 发布并关联

- [ ] **Publish** → **Publish function**
- [ ] **Add association**：

| 参数 | 值 |
|------|-----|
| Distribution | 选择 Distribution |
| Event type | **Viewer Request** |
| Cache behavior | **Default (*)** |

- [ ] 点击 **Add association**

> **注意**: 同一 Behavior 的同一 Event type 只能关联一个 Function。如果 URL 重写已关联到 Default (*) 的 Viewer Request，需要将两个 Function 的逻辑合并到一个 Function 中，或将 A/B 测试关联到其他 Behavior。在生产环境中，通常会将多个简单逻辑合并为一个 Function。

---

## Function 3: 地理位置重定向 (cf-geo-redirect)

### 功能说明

利用 CloudFront 自动注入的 `CloudFront-Viewer-Country` header，将中国大陆（CN）用户重定向到 `/cn/` 前缀路径，实现多区域内容分发。

### 步骤 3.1: 创建 Function

- [ ] **Functions** → **Create function**

| 参数 | 值 |
|------|-----|
| Name | `cf-geo-redirect` |
| Description | `Redirect CN visitors to /cn/ prefix path` |
| Runtime | **cloudfront-js-2.0** |

### 步骤 3.2: 编写 Function 代码

- [ ] 替换默认代码为：

```javascript
function handler(event) {
    var request = event.request;
    var headers = request.headers;
    var uri = request.uri;

    // CloudFront 自动注入的地理位置 header
    var country = '';
    if (headers['cloudfront-viewer-country']) {
        country = headers['cloudfront-viewer-country'].value;
    }

    // 重定向规则：CN 用户重定向到 /cn/ 前缀路径
    // 排除条件：已在 /cn/ 路径下、静态资源、API 请求
    if (country === 'CN'
        && !uri.startsWith('/cn/')
        && !uri.startsWith('/static/')
        && !uri.startsWith('/images/')
        && !uri.startsWith('/api/')) {

        var redirectUrl = '/cn' + uri;

        return {
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
                'location': { value: 'https://unice.keithyu.cloud' + redirectUrl },
                'cache-control': { value: 'no-cache, no-store, must-revalidate' }
            }
        };
    }

    return request;
}
```

- [ ] 点击 **Save changes**

### 步骤 3.3: 配置 CloudFront 转发地理位置 Header

CloudFront 默认不转发 `CloudFront-Viewer-Country` header。需要在 Cache Policy 或 Origin Request Policy 中启用。

- [ ] 打开 Distribution → **Behaviors** → 选择需要地理重定向的 Behavior → **Edit**
- [ ] 在 **Cache key and origin requests** 部分，确认 Origin request policy 为 `AllViewer` 或创建自定义策略包含 `CloudFront-Viewer-Country`

> **备选方案**：在 CloudFront Functions 中可直接读取 `cloudfront-viewer-country` header（CloudFront 自动注入），无需额外配置 Origin Request Policy。Function 在 Viewer Request 阶段执行时，CloudFront 已完成地理位置识别。

### 步骤 3.4: 测试 Function

- [ ] **Test** 标签页

**测试场景 1 - 中国用户访问首页**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Headers | `cloudfront-viewer-country: CN` |

- [ ] 确认返回 302 重定向到 `https://unice.keithyu.cloud/cn/`

**测试场景 2 - 日本用户访问首页**：

| 参数 | 值 |
|------|-----|
| URL path | `/` |
| Headers | `cloudfront-viewer-country: JP` |

- [ ] 确认请求正常通过（无重定向）

**测试场景 3 - 中国用户访问 API（不重定向）**：

| 参数 | 值 |
|------|-----|
| URL path | `/api/products` |
| Headers | `cloudfront-viewer-country: CN` |

- [ ] 确认请求正常通过（API 路径排除在外）

### 步骤 3.5: 发布并关联

- [ ] **Publish** → **Publish function**
- [ ] **Add association**（选择合适的 Behavior 和 Event type）

---

## 步骤 4: 综合验证

### 4.1 验证 URL 重写

```bash
# 访问友好 URL（应被重写到 /api/products）
curl -s https://unice.keithyu.cloud/products | jq .

# 访问带参数的友好 URL
curl -s https://unice.keithyu.cloud/products/123 | jq .
```

- [ ] 确认 `/products` 返回商品列表（说明成功重写到 `/api/products`）

### 4.2 验证 A/B 测试

```bash
# 不带 cookie 请求 - 查看分配的分组
curl -sI https://unice.keithyu.cloud/ | grep -i x-ab-group

# 带 cookie 请求 - 应保持分组
curl -sI -b "x-ab-group=A" https://unice.keithyu.cloud/ | grep -i x-ab-group

# 通过 debug 端点查看 Origin 收到的 header
curl -s -b "x-ab-group=B" https://unice.keithyu.cloud/api/debug | jq '.headers["x-ab-group"]'
```

- [ ] 确认不带 cookie 时被分配 A 或 B
- [ ] 确认带 cookie 时保持原有分组
- [ ] 确认 Origin 的 debug 端点能看到 `x-ab-group` header

### 4.3 验证地理重定向

```bash
# 模拟中国用户请求（通过 debug 端点观察，实际重定向需要真实的地理位置）
# 注意：curl 无法直接模拟 CloudFront 注入的地理 header，此验证依赖 Console Test 功能

# 查看 CloudFront 注入的地理位置 header
curl -s https://unice.keithyu.cloud/api/debug | jq '.headers | to_entries[] | select(.key | startswith("cloudfront-viewer"))'
```

- [ ] 确认可以看到 `cloudfront-viewer-country` 等地理位置 header

---

## 常见问题

| 问题 | 原因 | 解决方案 |
|------|------|----------|
| Function 发布失败 | 代码超过 10KB 或语法错误 | 检查代码大小和语法；Functions 不支持 ES6+ 的部分特性（如 let/const 在 JS 1.0 运行时） |
| 同一 Behavior 关联第二个 Function 报错 | 同一 Event type 只能关联一个 Function | 将多个逻辑合并到同一个 Function 中 |
| URL 重写后 404 | 重写后的路径没有匹配到正确的 Behavior 或 Origin | 检查 Behavior 路径优先级和 Origin 路由配置 |
| 地理重定向无限循环 | 重定向目标路径也匹配了重定向规则 | 确认代码中排除了 `/cn/` 前缀路径 |
| `cloudfront-viewer-country` 为空 | 未在 Cache Policy 中启用地理 header | 使用 cloudfront-js-2.0 运行时可直接读取，无需额外配置 |
