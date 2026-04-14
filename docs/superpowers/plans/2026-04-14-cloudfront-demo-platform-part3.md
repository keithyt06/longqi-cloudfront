## Phase 3: CloudFront + Security (Tasks 11-15)

> **Spec:** `docs/superpowers/specs/2026-04-14-cloudfront-demo-platform-design.md`
>
> **Reference modules:** `AWS/EC2-Workload/engineer-vscode-deployment/modules/cloudfront/` , `AWS/EC2-Workload/engineer-vscode-deployment/modules/waf/`
>
> **Existing resources:** VPC `vpc-086e15047c7f68e87` | ACM `arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2` | Route53 zone `keithyu.cloud`

---

### Task 11: CloudFront Functions

**目标**: 创建 3 个 CloudFront Functions，演示边缘计算的常见场景（URL 重写、A/B 测试、地理重定向）。所有函数使用 ECMAScript 5.1 兼容语法，运行在 CloudFront Functions runtime。

**Files to create:**
- `terraform/functions/cf-url-rewrite.js`
- `terraform/functions/cf-ab-test.js`
- `terraform/functions/cf-geo-redirect.js`

---

- [ ] **Step 1: 创建 functions 目录**

```bash
mkdir -p /root/keith-space/2026-project/longqi-cloudfront/terraform/functions
```

- [ ] **Step 2: 创建 cf-url-rewrite.js — 友好 URL 重写**

将 `/products/123` 重写为 `/api/products/123`，仅匹配 `/products/` 开头且不以静态资源扩展名结尾的路径。使 CloudFront Behavior 路由与应用内部路由解耦。

Write to `terraform/functions/cf-url-rewrite.js`:

```javascript
// CloudFront Function: URL 重写 (Viewer Request)
// 将友好 URL /products/123 重写为 /api/products/123
// 仅匹配 /products/ 开头且不以静态资源扩展名结尾的路径
// 绑定 Behavior: Default (*)
// Runtime: cloudfront-js-2.0 (ECMAScript 5.1 兼容)

function handler(event) {
    var request = event.request;
    var uri = request.uri;

    // 静态资源扩展名列表 — 这些路径不做重写
    var staticExts = [
        '.css', '.js', '.png', '.jpg', '.jpeg', '.gif',
        '.svg', '.ico', '.woff', '.woff2', '.ttf', '.eot',
        '.map', '.webp', '.avif'
    ];

    // 仅处理 /products/ 开头的路径
    if (uri.indexOf('/products/') === 0 || uri === '/products') {
        // 检查是否以静态资源扩展名结尾
        var isStatic = false;
        var lowerUri = uri.toLowerCase();
        for (var i = 0; i < staticExts.length; i++) {
            var ext = staticExts[i];
            // 检查 URI 是否以该扩展名结尾
            if (lowerUri.length >= ext.length &&
                lowerUri.indexOf(ext, lowerUri.length - ext.length) !== -1) {
                isStatic = true;
                break;
            }
        }

        // 非静态资源路径 — 添加 /api 前缀重写
        if (!isStatic) {
            request.uri = '/api' + uri;
        }
    }

    return request;
}
```

- [ ] **Step 3: 创建 cf-ab-test.js — A/B 测试分流**

读取 `x-ab-group` cookie，若存在直接使用；若不存在，随机分配 A 或 B 组。将分组写入请求 cookie（通过 Origin Request Policy 转发到源站），并添加 `X-AB-Group` header 供源站直接读取。

> **注意**: CloudFront Functions viewer-request 阶段无法直接设置浏览器端 Set-Cookie。源站 Express 中间件需检测 `x-ab-new-assignment` header，据此在响应中设置 `Set-Cookie: x-ab-group=<A|B>` 完成浏览器端持久化。

Write to `terraform/functions/cf-ab-test.js`:

```javascript
// CloudFront Function: A/B 测试分流 (Viewer Request)
// 读取 x-ab-group cookie，无则随机分配 A/B 组
// 将分组信息通过 header 传递给源站
// 绑定 Behavior: Default (*)
// Runtime: cloudfront-js-2.0 (ECMAScript 5.1 兼容)
//
// 工作流:
//   1. 检查 x-ab-group cookie
//   2. 若缺失 -> Math.random() 分配 A (50%) 或 B (50%)
//   3. 将分组写入请求 cookie（ORP 转发到源站）
//   4. 添加 X-AB-Group header（源站可直接读取）
//   5. 若为新分配，添加 x-ab-new-assignment header 通知源站设置 Set-Cookie

function handler(event) {
    var request = event.request;
    var cookies = request.cookies;
    var abGroup;

    // 检查是否已有 A/B 分组 cookie
    if (cookies['x-ab-group'] && cookies['x-ab-group'].value) {
        // 已有分组 — 验证值合法性
        var existing = cookies['x-ab-group'].value;
        if (existing === 'A' || existing === 'B') {
            abGroup = existing;
        } else {
            // cookie 值非法，重新分配
            abGroup = (Math.random() < 0.5) ? 'A' : 'B';
            request.cookies['x-ab-group'] = { value: abGroup };
            request.headers['x-ab-new-assignment'] = { value: 'true' };
        }
    } else {
        // 新用户 — 随机分配 A 或 B 组（50/50 概率）
        abGroup = (Math.random() < 0.5) ? 'A' : 'B';

        // 将 cookie 写入请求（通过 Origin Request Policy 转发到源站）
        request.cookies['x-ab-group'] = { value: abGroup };

        // 标记为新分配，源站据此在响应中设置 Set-Cookie 持久化
        request.headers['x-ab-new-assignment'] = { value: 'true' };
    }

    // 添加 X-AB-Group header 供源站使用
    // 比从 cookie 读取更可靠（header 不受 cookie 解析影响）
    request.headers['x-ab-group'] = { value: abGroup };

    return request;
}
```

- [ ] **Step 4: 创建 cf-geo-redirect.js — 地理位置重定向**

利用 CloudFront 自动注入的 `CloudFront-Viewer-Country` header 判断访问者国家。CN（中国大陆）用户自动 302 重定向到 `/cn/` 前缀路径。排除 `/api/`、`/static/`、`/images/` 路径避免影响 API 调用和静态资源加载。

Write to `terraform/functions/cf-geo-redirect.js`:

```javascript
// CloudFront Function: 地理位置重定向 (Viewer Request)
// 读取 CloudFront-Viewer-Country header，CN 用户重定向到 /cn/ 前缀
// 排除 /api/ /static/ /images/ 路径，避免影响 API 和静态资源
// 绑定 Behavior: Default (*)
// Runtime: cloudfront-js-2.0 (ECMAScript 5.1 兼容)
//
// 前提条件:
//   Origin Request Policy 必须包含 CloudFront-Viewer-Country header
//   （allViewerAndWhitelistCloudFront 行为自动包含）

function handler(event) {
    var request = event.request;
    var uri = request.uri;
    var headers = request.headers;

    // 排除路径 — 这些路径不做地理重定向
    var excludePrefixes = ['/api/', '/static/', '/images/', '/cn/', '/premium/'];
    for (var i = 0; i < excludePrefixes.length; i++) {
        if (uri.indexOf(excludePrefixes[i]) === 0) {
            return request;
        }
    }

    // 排除根路径 /cn（不带斜杠的情况）
    if (uri === '/cn') {
        return request;
    }

    // 读取 CloudFront 注入的国家代码 header
    var countryHeader = headers['cloudfront-viewer-country'];
    if (!countryHeader || !countryHeader.value) {
        // 无国家信息 — 不做处理
        return request;
    }

    var country = countryHeader.value.toUpperCase();

    // CN（中国大陆）用户 — 302 重定向到 /cn/ 前缀路径
    if (country === 'CN') {
        var redirectUri = '/cn' + uri;
        // 保留 query string
        var qs = request.querystring;
        var qsStr = '';
        var keys = Object.keys(qs);
        if (keys.length > 0) {
            var pairs = [];
            for (var j = 0; j < keys.length; j++) {
                var key = keys[j];
                var val = qs[key];
                if (val.multiValue) {
                    for (var k = 0; k < val.multiValue.length; k++) {
                        pairs.push(key + '=' + val.multiValue[k].value);
                    }
                } else {
                    pairs.push(key + '=' + val.value);
                }
            }
            qsStr = '?' + pairs.join('&');
        }

        var response = {
            statusCode: 302,
            statusDescription: 'Found',
            headers: {
                'location': { value: redirectUri + qsStr },
                'cache-control': { value: 'no-store, no-cache' }
            }
        };
        return response;
    }

    return request;
}
```

- [ ] **Step 5: 验证函数语法**

```bash
# 确认无 ES6+ 语法（let, const, =>, `template`, class 等）
cd /root/keith-space/2026-project/longqi-cloudfront/terraform/functions
for f in cf-*.js; do
  echo "--- Checking $f ---"
  # 检查 let/const 声明
  grep -n '\blet\b\|\bconst\b' "$f" && echo "WARN: found let/const" || echo "OK: no let/const"
  # 检查箭头函数
  grep -n '=>' "$f" && echo "WARN: found arrow function" || echo "OK: no arrow function"
  # 检查模板字面量
  grep -n '`' "$f" && echo "WARN: found template literal" || echo "OK: no template literal"
done
```

---

### Task 12: CloudFront Distribution 模块

**目标**: 创建 CloudFront Distribution 模块，包含 S3 OAC 源站、ALB VPC Origin 源站、10 条 ordered cache behavior、自定义缓存策略、CloudFront Functions 关联、自定义错误页面、签名 URL 密钥组、Route53 记录。

**Files to create:**
- `terraform/modules/cloudfront/main.tf`
- `terraform/modules/cloudfront/variables.tf`
- `terraform/modules/cloudfront/outputs.tf`

---

- [ ] **Step 1: 创建模块目录**

```bash
mkdir -p /root/keith-space/2026-project/longqi-cloudfront/terraform/modules/cloudfront
```

- [ ] **Step 2: 创建 main.tf — CloudFront Distribution 完整配置**

Write to `terraform/modules/cloudfront/main.tf`:

```hcl
# =============================================================================
# CloudFront Distribution 模块
# 包含: OAC, VPC Origin, Cache Policy, Origin Request Policy,
#        CloudFront Functions, Distribution, Signed URL, Route53
# =============================================================================

# -----------------------------------------------------------------------------
# AWS 托管缓存策略 / Origin Request Policy ID
# 使用硬编码 ID 比 data source 更可靠（AWS 托管策略 ID 永不变更）
# -----------------------------------------------------------------------------
locals {
  # AWS 托管 Cache Policy
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  # 选择要绑定到 Default Behavior 的 CloudFront Function
  # CloudFront 每个 Behavior 的每个事件类型只允许关联 1 个函数
  cf_function_arn = (
    var.default_cf_function == "url-rewrite"  ? aws_cloudfront_function.url_rewrite.arn :
    var.default_cf_function == "ab-test"      ? aws_cloudfront_function.ab_test.arn :
    var.default_cf_function == "geo-redirect" ? aws_cloudfront_function.geo_redirect.arn :
    null
  )
}

# -----------------------------------------------------------------------------
# S3 Origin Access Control (OAC)
# 替代已废弃的 OAI，使用 SigV4 签名确保只有 CloudFront 可访问 S3
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_access_control" "s3" {
  name                              = "${var.name}-s3-oac"
  description                       = "OAC for ${var.name} S3 static content bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# -----------------------------------------------------------------------------
# CloudFront VPC Origin — 连接 Internal ALB
# 在 VPC 内创建 ENI，通过 AWS 内部网络直连 Internal ALB
# ALB 无需公网 IP，从根本上消除绕过 CDN 直接攻击源站的风险
# -----------------------------------------------------------------------------
resource "aws_cloudfront_vpc_origin" "alb" {
  vpc_origin_endpoint_config {
    name                   = "${var.name}-alb-vpc-origin"
    arn                    = var.alb_arn
    http_port              = 80
    https_port             = 443
    origin_protocol_policy = "http-only"
    origin_ssl_protocols {
      items    = ["TLSv1.2"]
      quantity = 1
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-origin"
  })
}

# -----------------------------------------------------------------------------
# 自定义 Cache Policy: ProductCache (3600s)
# 商品 API 缓存策略 — 1 小时 TTL，按 Query String 区分不同页码/筛选条件
# Cache Key: 全部 QS + Accept + Accept-Language header（无 cookie）
# -----------------------------------------------------------------------------
resource "aws_cloudfront_cache_policy" "product_cache" {
  name        = "${var.name}-product-cache"
  comment     = "商品 API 缓存策略: 3600s TTL, QS+Accept+Accept-Language 作为缓存键"
  default_ttl = 3600
  max_ttl     = 86400
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Accept", "Accept-Language"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# -----------------------------------------------------------------------------
# 自定义 Cache Policy: PageCache (60s)
# SSR 页面缓存策略 — 60 秒短 TTL，兼顾性能和内容新鲜度
# Cache Key: x-trace-id + aws-waf-token cookie, 全部 QS, Host + Accept header
# 仅转发 2 个 cookie 避免不必要的 cookie 破坏缓存命中率
# -----------------------------------------------------------------------------
resource "aws_cloudfront_cache_policy" "page_cache" {
  name        = "${var.name}-page-cache"
  comment     = "SSR 页面缓存策略: 60s TTL, 仅 trace+waf cookie 作为缓存键"
  default_ttl = 60
  max_ttl     = 300
  min_ttl     = 0

  parameters_in_cache_key_and_forwarded_to_origin {
    cookies_config {
      cookie_behavior = "whitelist"
      cookies {
        items = ["x-trace-id", "aws-waf-token"]
      }
    }

    headers_config {
      header_behavior = "whitelist"
      headers {
        items = ["Host", "Accept"]
      }
    }

    query_strings_config {
      query_string_behavior = "all"
    }

    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
  }
}

# -----------------------------------------------------------------------------
# 自定义 Origin Request Policy: AllViewerExceptHostHeader
# 转发所有 viewer 信息到源站（排除 Host header），附加 CloudFront 地理位置 header
# Host header 由 CloudFront 自动替换为源站域名，避免 ALB 路由混乱
# -----------------------------------------------------------------------------
resource "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name    = "${var.name}-all-viewer-except-host"
  comment = "转发所有 viewer 信息到源站（排除 Host），附加 CF 地理 header"

  cookies_config {
    cookie_behavior = "all"
  }

  headers_config {
    header_behavior = "allViewerAndWhitelistCloudFront"
    headers {
      items = [
        "CloudFront-Viewer-Country",
        "CloudFront-Viewer-City",
        "CloudFront-Is-Desktop-Viewer",
        "CloudFront-Is-Mobile-Viewer",
        "CloudFront-Is-Tablet-Viewer"
      ]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }
}

# -----------------------------------------------------------------------------
# CloudFront Functions x3
# 所有函数在创建时即发布到 LIVE stage，可立即关联到 Behavior
# 每个 Behavior 每个事件类型（viewer-request / viewer-response）只允许 1 个函数
# 通过 var.default_cf_function 选择绑定到 Default Behavior 的函数
# -----------------------------------------------------------------------------
resource "aws_cloudfront_function" "url_rewrite" {
  name    = "${var.name}-cf-url-rewrite"
  runtime = "cloudfront-js-2.0"
  comment = "URL 重写: /products/123 -> /api/products/123"
  publish = true
  code    = file("${path.root}/functions/cf-url-rewrite.js")
}

resource "aws_cloudfront_function" "ab_test" {
  name    = "${var.name}-cf-ab-test"
  runtime = "cloudfront-js-2.0"
  comment = "A/B 测试分流: 随机分配 A/B 组并通过 header 传递给源站"
  publish = true
  code    = file("${path.root}/functions/cf-ab-test.js")
}

resource "aws_cloudfront_function" "geo_redirect" {
  name    = "${var.name}-cf-geo-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "地理重定向: CN 用户 302 到 /cn/ 前缀路径"
  publish = true
  code    = file("${path.root}/functions/cf-geo-redirect.js")
}

# -----------------------------------------------------------------------------
# 签名 URL 密钥对（条件创建: var.enable_signed_url）
# RSA 2048 位密钥对 — 公钥注册到 CloudFront，私钥存储到本地供 EC2 签发签名 URL
# -----------------------------------------------------------------------------
resource "tls_private_key" "cf_signed" {
  count     = var.enable_signed_url ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "aws_cloudfront_public_key" "main" {
  count       = var.enable_signed_url ? 1 : 0
  name        = "${var.name}-cf-signed-key"
  encoded_key = tls_private_key.cf_signed[0].public_key_pem
  comment     = "Public key for ${var.name} signed URL verification"
}

resource "aws_cloudfront_key_group" "main" {
  count   = var.enable_signed_url ? 1 : 0
  name    = "${var.name}-cf-key-group"
  items   = [aws_cloudfront_public_key.main[0].id]
  comment = "Key group for ${var.name} premium content signed URLs"
}

resource "local_file" "cf_private_key" {
  count           = var.enable_signed_url ? 1 : 0
  content         = tls_private_key.cf_signed[0].private_key_pem
  filename        = "${path.root}/keys/cf-private-key.pem"
  file_permission = "0600"
}

# -----------------------------------------------------------------------------
# CloudFront Distribution
# 双源架构: S3 (OAC) + ALB (VPC Origin)
# 10 ordered cache behaviors + 1 default — 严格匹配 spec Section 4.2
# -----------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "main" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.name} demo platform"
  default_root_object = ""
  price_class         = var.price_class
  aliases             = [var.custom_domain]
  web_acl_id          = var.waf_web_acl_arn

  # Continuous Deployment 策略（条件关联）
  continuous_deployment_policy_id = var.cd_policy_id != "" ? var.cd_policy_id : null

  # ===========================================================================
  # Origin 1: S3 静态内容桶 (OAC 访问)
  # ===========================================================================
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.s3.id
  }

  # ===========================================================================
  # Origin 2: Internal ALB (VPC Origin)
  # CloudFront 通过 VPC 内 ENI 直连 ALB，流量不经公网
  # ===========================================================================
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-vpc-origin"

    vpc_origin_config {
      vpc_origin_id            = aws_cloudfront_vpc_origin.alb.id
      origin_keepalive_timeout = 60
      origin_read_timeout      = 60
    }
  }

  # ===========================================================================
  # Ordered Cache Behavior 1: /static/*
  # CSS/JS/字体 → S3 (OAC), CachingOptimized 24h, 无 cookie/QS/header 转发
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/static/*"
    target_origin_id = "s3-origin"

    cache_policy_id = local.cache_policy_caching_optimized

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 2: /images/*
  # 商品图片 → S3 (OAC), CachingOptimized 24h
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/images/*"
    target_origin_id = "s3-origin"

    cache_policy_id = local.cache_policy_caching_optimized

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 3: /api/products*
  # 商品列表 API → ALB (VPC), ProductCache 3600s
  # 按 QS（page/category/sort）区分缓存，Accept/Accept-Language 进缓存键
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/products*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id          = aws_cloudfront_cache_policy.product_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 4: /api/cart*
  # 购物车 → ALB (VPC), CachingDisabled, 全部转发
  # 强依赖用户身份 cookie，必须禁用缓存
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/cart*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 5: /api/user*
  # 登录/注册/UUID 绑定 → ALB (VPC), CachingDisabled, 全部转发
  # 涉及 Set-Cookie 操作，必须禁用缓存
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/user*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 6: /api/orders*
  # 订单数据 → ALB (VPC), CachingDisabled, 全部转发
  # 高度个性化数据，禁用缓存
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/orders*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 7: /api/debug*
  # 调试端点 → ALB (VPC), CachingDisabled, 全部转发
  # 完全透传以便观察 CloudFront 注入的所有 Header
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/debug*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 8: /api/delay/*
  # 延迟模拟 → ALB (VPC), CachingDisabled, 无额外转发
  # 用于测试 CloudFront 超时和重试行为，路径参数已包含延迟值
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/delay/*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id = local.cache_policy_caching_disabled

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 9: /api/health*
  # 健康检查 → ALB (VPC), CachingDisabled, 无额外转发
  # ALB/CloudFront 健康检查端点，不需要 cookie 或 header 转发
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/api/health*"
    target_origin_id = "alb-vpc-origin"

    cache_policy_id = local.cache_policy_caching_disabled

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # ===========================================================================
  # Ordered Cache Behavior 10: /premium/*
  # 会员内容 → S3 (OAC), CachingOptimized, 签名 URL 保护（条件）
  # 需要 Trusted Key Group 验证签名，无签名请求返回 403
  # ===========================================================================
  ordered_cache_behavior {
    path_pattern     = "/premium/*"
    target_origin_id = "s3-origin"

    cache_policy_id = local.cache_policy_caching_optimized

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # 签名 URL — 启用后要求所有请求携带有效签名
    trusted_key_groups = var.enable_signed_url ? [aws_cloudfront_key_group.main[0].id] : []
  }

  # ===========================================================================
  # Default Cache Behavior: *
  # SSR 页面 → ALB (VPC), PageCache 60s
  # 仅 x-trace-id + aws-waf-token cookie 进缓存键，全部 QS 转发
  # 关联 CloudFront Function（通过 var.default_cf_function 选择）
  # ===========================================================================
  default_cache_behavior {
    target_origin_id = "alb-vpc-origin"

    cache_policy_id          = aws_cloudfront_cache_policy.page_cache.id
    origin_request_policy_id = aws_cloudfront_origin_request_policy.all_viewer_except_host.id

    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # CloudFront Function 关联（viewer-request）
    # 每个 Behavior 每个事件类型只允许 1 个函数
    # 通过 var.default_cf_function 选择: url-rewrite / ab-test / geo-redirect / none
    dynamic "function_association" {
      for_each = local.cf_function_arn != null ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = local.cf_function_arn
      }
    }
  }

  # ===========================================================================
  # 自定义错误页面 — 品牌化友好错误体验
  # 4xx/5xx 错误替换为 S3 上的自定义 HTML 页面
  # 5xx 缓存 TTL 较短（60s），因为通常是暂时性错误
  # ===========================================================================
  custom_error_response {
    error_code            = 403
    response_page_path    = "/static/errors/403.html"
    response_code         = 403
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 404
    response_page_path    = "/static/errors/404.html"
    response_code         = 404
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 500
    response_page_path    = "/static/errors/500.html"
    response_code         = 500
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 502
    response_page_path    = "/static/errors/502.html"
    response_code         = 502
    error_caching_min_ttl = 60
  }

  # ===========================================================================
  # TLS 证书 — ACM 通配符证书 *.keithyu.cloud
  # ===========================================================================
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  # ===========================================================================
  # 地理限制（条件启用）
  # ===========================================================================
  restrictions {
    geo_restriction {
      restriction_type = var.enable_geo_restriction ? var.geo_restriction_type : "none"
      locations        = var.enable_geo_restriction ? var.geo_restriction_locations : []
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-cloudfront"
  })
}

# -----------------------------------------------------------------------------
# Route53 ALIAS 记录 — unice.keithyu.cloud -> CloudFront Distribution
# 同时创建 A 和 AAAA 记录支持 IPv4/IPv6 双栈访问
# -----------------------------------------------------------------------------
resource "aws_route53_record" "cloudfront_a" {
  zone_id = var.route53_zone_id
  name    = var.custom_domain
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "cloudfront_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.custom_domain
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
    evaluate_target_health = false
  }
}
```

- [ ] **Step 3: 创建 variables.tf — CloudFront 模块输入变量**

Write to `terraform/modules/cloudfront/variables.tf`:

```hcl
# =============================================================================
# CloudFront 模块 — 输入变量
# =============================================================================

# -----------------------------------------------------------------------------
# 基础配置
# -----------------------------------------------------------------------------
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

variable "price_class" {
  description = "CloudFront 价格等级 (PriceClass_All / PriceClass_200 / PriceClass_100)"
  type        = string
  default     = "PriceClass_All"
}

# -----------------------------------------------------------------------------
# S3 源站
# -----------------------------------------------------------------------------
variable "s3_bucket_regional_domain_name" {
  description = "S3 桶的区域域名 (bucket.s3.ap-northeast-1.amazonaws.com)"
  type        = string
}

variable "s3_bucket_id" {
  description = "S3 桶 ID（用于 OAC 策略引用）"
  type        = string
}

# -----------------------------------------------------------------------------
# ALB 源站 (VPC Origin)
# -----------------------------------------------------------------------------
variable "alb_dns_name" {
  description = "Internal ALB 的 DNS 名称"
  type        = string
}

variable "alb_arn" {
  description = "Internal ALB 的 ARN（VPC Origin 用于创建 ENI 连接）"
  type        = string
}

# -----------------------------------------------------------------------------
# 域名与证书
# -----------------------------------------------------------------------------
variable "custom_domain" {
  description = "CloudFront 自定义域名 (unice.keithyu.cloud)"
  type        = string
}

variable "acm_certificate_arn" {
  description = "us-east-1 ACM 通配符证书 ARN (*.keithyu.cloud)"
  type        = string
}

variable "route53_zone_id" {
  description = "Route53 Hosted Zone ID (keithyu.cloud)"
  type        = string
}

# -----------------------------------------------------------------------------
# WAF
# -----------------------------------------------------------------------------
variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN（为空则不关联 WAF）"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Feature Flags
# -----------------------------------------------------------------------------
variable "enable_signed_url" {
  description = "是否启用签名 URL（创建 RSA 密钥对和 Key Group）"
  type        = bool
  default     = true
}

variable "enable_geo_restriction" {
  description = "是否启用地理限制"
  type        = bool
  default     = true
}

variable "geo_restriction_type" {
  description = "地理限制类型 (whitelist / blacklist)"
  type        = string
  default     = "blacklist"
}

variable "geo_restriction_locations" {
  description = "地理限制国家代码列表 (ISO 3166-1 alpha-2)"
  type        = list(string)
  default     = ["KP", "IR"]
}

variable "default_cf_function" {
  description = "绑定到 Default Behavior viewer-request 的 CloudFront Function (url-rewrite / ab-test / geo-redirect / none)"
  type        = string
  default     = "url-rewrite"

  validation {
    condition     = contains(["url-rewrite", "ab-test", "geo-redirect", "none"], var.default_cf_function)
    error_message = "default_cf_function must be one of: url-rewrite, ab-test, geo-redirect, none"
  }
}

# -----------------------------------------------------------------------------
# Continuous Deployment
# -----------------------------------------------------------------------------
variable "cd_policy_id" {
  description = "Continuous Deployment Policy ID（为空则不关联 CD 策略）"
  type        = string
  default     = ""
}
```

- [ ] **Step 4: 创建 outputs.tf — CloudFront 模块输出**

Write to `terraform/modules/cloudfront/outputs.tf`:

```hcl
# =============================================================================
# CloudFront 模块 — 输出
# =============================================================================

output "distribution_id" {
  description = "CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.main.id
}

output "distribution_arn" {
  description = "CloudFront Distribution ARN"
  value       = aws_cloudfront_distribution.main.arn
}

output "distribution_domain" {
  description = "CloudFront Distribution 域名 (d1234.cloudfront.net)"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "distribution_hosted_zone_id" {
  description = "CloudFront Distribution Hosted Zone ID (Route53 ALIAS 用)"
  value       = aws_cloudfront_distribution.main.hosted_zone_id
}

output "vpc_origin_id" {
  description = "VPC Origin ID"
  value       = aws_cloudfront_vpc_origin.alb.id
}

output "vpc_origin_arn" {
  description = "VPC Origin ARN"
  value       = aws_cloudfront_vpc_origin.alb.arn
}

output "oac_id" {
  description = "S3 Origin Access Control ID"
  value       = aws_cloudfront_origin_access_control.s3.id
}

output "product_cache_policy_id" {
  description = "ProductCache 自定义缓存策略 ID"
  value       = aws_cloudfront_cache_policy.product_cache.id
}

output "page_cache_policy_id" {
  description = "PageCache 自定义缓存策略 ID"
  value       = aws_cloudfront_cache_policy.page_cache.id
}

output "origin_request_policy_id" {
  description = "AllViewerExceptHostHeader 自定义 ORP ID"
  value       = aws_cloudfront_origin_request_policy.all_viewer_except_host.id
}

output "cf_function_url_rewrite_arn" {
  description = "cf-url-rewrite CloudFront Function ARN"
  value       = aws_cloudfront_function.url_rewrite.arn
}

output "cf_function_ab_test_arn" {
  description = "cf-ab-test CloudFront Function ARN"
  value       = aws_cloudfront_function.ab_test.arn
}

output "cf_function_geo_redirect_arn" {
  description = "cf-geo-redirect CloudFront Function ARN"
  value       = aws_cloudfront_function.geo_redirect.arn
}

output "key_group_id" {
  description = "签名 URL Key Group ID（未启用时为 null）"
  value       = var.enable_signed_url ? aws_cloudfront_key_group.main[0].id : null
}

output "signed_url_private_key_path" {
  description = "签名 URL 私钥本地路径（未启用时为 null）"
  value       = var.enable_signed_url ? local_file.cf_private_key[0].filename : null
}
```

- [ ] **Step 5: 验证 Behavior 数量匹配 spec Section 4.2**

确认共 10 条 ordered_cache_behavior + 1 条 default_cache_behavior = 11 条，覆盖所有路径模式：

| # | Path Pattern | Origin | Cache Policy | ORP |
|---|---|---|---|---|
| 1 | `/static/*` | S3 (OAC) | CachingOptimized | - |
| 2 | `/images/*` | S3 (OAC) | CachingOptimized | - |
| 3 | `/api/products*` | ALB (VPC) | ProductCache 3600s | AllViewerExceptHost |
| 4 | `/api/cart*` | ALB (VPC) | CachingDisabled | AllViewerExceptHost |
| 5 | `/api/user*` | ALB (VPC) | CachingDisabled | AllViewerExceptHost |
| 6 | `/api/orders*` | ALB (VPC) | CachingDisabled | AllViewerExceptHost |
| 7 | `/api/debug*` | ALB (VPC) | CachingDisabled | AllViewerExceptHost |
| 8 | `/api/delay/*` | ALB (VPC) | CachingDisabled | - |
| 9 | `/api/health*` | ALB (VPC) | CachingDisabled | - |
| 10 | `/premium/*` | S3 (OAC) | CachingOptimized | - (+ TrustedKeyGroups) |
| Default | `*` | ALB (VPC) | PageCache 60s | AllViewerExceptHost (+ CF Function) |

---

### Task 13: WAF 模块

**目标**: 创建 WAF Web ACL（部署在 us-east-1，CloudFront 全球服务要求），包含 6 条规则：3 条 AWS 托管规则 + 1 条 Bot Control（条件启用）+ 1 条速率限制 + 1 条地理封禁。

**Files to create:**
- `terraform/modules/waf/main.tf`
- `terraform/modules/waf/variables.tf`
- `terraform/modules/waf/outputs.tf`
- `terraform/modules/waf/versions.tf`

---

- [ ] **Step 1: 创建模块目录**

```bash
mkdir -p /root/keith-space/2026-project/longqi-cloudfront/terraform/modules/waf
```

- [ ] **Step 2: 创建 versions.tf — Provider 约束**

WAF Web ACL 必须在 us-east-1 才能与 CloudFront 关联。根模块通过 `providers = { aws = aws.us_east_1 }` 传入 us-east-1 provider。

Write to `terraform/modules/waf/versions.tf`:

```hcl
# =============================================================================
# WAF 模块 — Provider 约束
# WAF Web ACL 必须部署在 us-east-1 才能与 CloudFront 关联
# 根模块通过 providers = { aws = aws.us_east_1 } 传入正确区域的 provider
# =============================================================================
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}
```

- [ ] **Step 3: 创建 main.tf — WAF Web ACL 完整规则配置**

Write to `terraform/modules/waf/main.tf`:

```hcl
# =============================================================================
# WAF Web ACL for CloudFront (us-east-1)
# 6 条规则: Common Rule Set, Known Bad Inputs, Bot Control (条件),
#           Rate Limit, IP Reputation, Geo Block
# =============================================================================

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.name}-waf"
  description = "WAF Web ACL for ${var.name} CloudFront distribution"
  scope       = "CLOUDFRONT"

  # 默认动作: 允许 — 只有匹配规则的请求才被处理
  default_action {
    allow {}
  }

  # ===========================================================================
  # Rule 1: AWS Common Rule Set (优先级 1, Count 模式)
  # 覆盖 OWASP Top 10 常见攻击: SQL 注入、XSS、SSRF 等
  # 建议: 初始设为 Count 观察误报，确认无误后切换为 Block (override_action { none {} })
  # ===========================================================================
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 2: AWS Known Bad Inputs (优先级 2, Block)
  # 检测已知恶意输入模式: Log4j 漏洞利用 payload、恶意 User-Agent 等
  # ===========================================================================
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 3: AWS Bot Control — TARGETED 级别 (优先级 3, 条件启用)
  # 基于行为分析 + ML 模型检测高级爬虫和自动化工具
  # 配合 WAF JS SDK (aws-waf-token cookie) 区分真实浏览器和无头脚本
  # 费用: $10/月基础费 + $1/百万请求，通过 enable_bot_control 控制
  #
  # managed_rule_group_configs 设置 inspection_level = TARGETED:
  #   - Common 级别: HTTP 指纹识别已知机器人
  #   - Targeted 级别: 在 Common 基础上增加行为分析、ML 模型、JS 验证
  # ===========================================================================
  dynamic "rule" {
    for_each = var.enable_bot_control ? [1] : []
    content {
      name     = "AWS-AWSManagedRulesBotControlRuleSet"
      priority = 3

      override_action {
        none {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          # TARGETED inspection level — 启用行为分析和 ML 检测
          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = "TARGETED"
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-bot-control"
        sampled_requests_enabled   = true
      }
    }
  }

  # ===========================================================================
  # Rule 4: Rate Limit — 2000 次/5 分钟 (优先级 4, Block)
  # 同一 IP 在 5 分钟评估窗口内超过 2000 次请求将被封禁
  # 防止暴力破解、简单 DDoS、API 滥用
  # ===========================================================================
  rule {
    name     = "RateLimitRule"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 5: AWS IP Reputation List (优先级 5, Count)
  # AWS 维护的恶意 IP 信誉库: 僵尸网络节点、匿名代理、Tor 出口节点等
  # Count 模式用于监控，避免误封正常用户
  # ===========================================================================
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 5

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 6: Geo Block — 自定义国家封禁 (优先级 6, Block)
  # 封禁来自指定国家的所有请求，配合 CloudFront geo_restriction 使用
  # 国家代码列表通过 var.geo_block_countries 传入
  # 仅在提供了国家代码列表时才创建此规则
  # ===========================================================================
  dynamic "rule" {
    for_each = length(var.geo_block_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlockRule"
      priority = 6

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.geo_block_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  # ===========================================================================
  # Web ACL 全局可观测性配置
  # ===========================================================================
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-waf"
  })
}
```

- [ ] **Step 4: 创建 variables.tf — WAF 模块输入变量**

Write to `terraform/modules/waf/variables.tf`:

```hcl
# =============================================================================
# WAF 模块 — 输入变量
# =============================================================================

variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

variable "enable_bot_control" {
  description = "是否启用 Bot Control TARGETED 级别（额外费用: $10/月 + $1/百万请求）"
  type        = bool
  default     = false
}

variable "rate_limit" {
  description = "速率限制: 同一 IP 在 5 分钟评估窗口内允许的最大请求数"
  type        = number
  default     = 2000
}

variable "geo_block_countries" {
  description = "要封禁的国家代码列表 (ISO 3166-1 alpha-2)，空列表则不创建 Geo Block 规则"
  type        = list(string)
  default     = ["KP", "IR"]
}
```

- [ ] **Step 5: 创建 outputs.tf — WAF 模块输出**

Write to `terraform/modules/waf/outputs.tf`:

```hcl
# =============================================================================
# WAF 模块 — 输出
# =============================================================================

output "web_acl_arn" {
  description = "WAF Web ACL ARN（关联到 CloudFront Distribution 的 web_acl_id）"
  value       = aws_wafv2_web_acl.main.arn
}

output "web_acl_id" {
  description = "WAF Web ACL ID"
  value       = aws_wafv2_web_acl.main.id
}

output "web_acl_name" {
  description = "WAF Web ACL 名称"
  value       = aws_wafv2_web_acl.main.name
}
```

- [ ] **Step 6: 验证 WAF 规则优先级和动作**

| 规则 | 优先级 | 动作 | 条件 |
|---|---|---|---|
| AWS Common Rule Set | 1 | Count | 始终创建 |
| AWS Known Bad Inputs | 2 | Block | 始终创建 |
| AWS Bot Control (TARGETED) | 3 | Block/Challenge | `enable_bot_control = true` |
| Rate Limit 2000/5min | 4 | Block | 始终创建 |
| IP Reputation | 5 | Count | 始终创建 |
| Geo Block | 6 | Block | `geo_block_countries` 非空 |

---

### Task 14: CloudFront Continuous Deployment 模块

**目标**: 创建 Staging Distribution 和 Continuous Deployment Policy，支持灰度发布。Staging 分发镜像 Production 的完整配置，通过 SingleWeight (5%) 或 SingleHeader 策略分流真实流量到 Staging 进行验证。

**Files to create:**
- `terraform/modules/cloudfront-cd/main.tf`
- `terraform/modules/cloudfront-cd/variables.tf`
- `terraform/modules/cloudfront-cd/outputs.tf`

---

- [ ] **Step 1: 创建模块目录**

```bash
mkdir -p /root/keith-space/2026-project/longqi-cloudfront/terraform/modules/cloudfront-cd
```

- [ ] **Step 2: 创建 main.tf — Staging Distribution + CD Policy**

> **依赖关系**: cd 模块不依赖 cloudfront 模块的 Production Distribution。两个 Distribution 共享相同的 Origin（S3 / ALB VPC Origin），通过变量传入各资源 ID。根模块将 cd 模块的 `cd_policy_id` 传给 cloudfront 模块，cloudfront 模块在 Production Distribution 上关联该策略。

Write to `terraform/modules/cloudfront-cd/main.tf`:

```hcl
# =============================================================================
# CloudFront Continuous Deployment 模块
# 创建 Staging Distribution + CD Policy，支持灰度发布
#
# 工作流:
#   1. cd 模块创建 Staging Distribution (staging = true) + CD Policy
#   2. cloudfront 模块在 Production Distribution 上关联 cd_policy_id
#   3. CD Policy 根据 SingleWeight 或 SingleHeader 策略分流流量
#   4. 验证通过后通过 AWS CLI/Console promote Staging 配置到 Production
# =============================================================================

# AWS 托管缓存策略 ID（与 Production 一致）
locals {
  cache_policy_caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  cache_policy_caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

# -----------------------------------------------------------------------------
# Staging Distribution
# staging = true 标记为暂存分发，不直接服务公网流量
# 配置与 Production 完全相同（双源 + 全部 Behavior）
# 不设置 aliases（CNAME 由 CD Policy 自动处理）
# -----------------------------------------------------------------------------
resource "aws_cloudfront_distribution" "staging" {
  enabled         = true
  staging         = true
  is_ipv6_enabled = true
  comment         = "${var.name} Staging Distribution for Continuous Deployment"
  price_class     = var.price_class
  web_acl_id      = var.waf_web_acl_arn

  # ===========================================================================
  # Origin 1: S3 静态内容桶 (OAC)
  # ===========================================================================
  origin {
    domain_name              = var.s3_bucket_regional_domain_name
    origin_id                = "s3-origin"
    origin_access_control_id = var.oac_id
  }

  # ===========================================================================
  # Origin 2: Internal ALB (VPC Origin)
  # ===========================================================================
  origin {
    domain_name = var.alb_dns_name
    origin_id   = "alb-vpc-origin"

    vpc_origin_config {
      vpc_origin_id            = var.vpc_origin_id
      origin_keepalive_timeout = 60
      origin_read_timeout      = 60
    }
  }

  # ===========================================================================
  # 10 Ordered Cache Behaviors — 与 Production 完全相同
  # ===========================================================================

  # 1. /static/*
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "s3-origin"
    cache_policy_id        = local.cache_policy_caching_optimized
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # 2. /images/*
  ordered_cache_behavior {
    path_pattern           = "/images/*"
    target_origin_id       = "s3-origin"
    cache_policy_id        = local.cache_policy_caching_optimized
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # 3. /api/products*
  ordered_cache_behavior {
    path_pattern             = "/api/products*"
    target_origin_id         = "alb-vpc-origin"
    cache_policy_id          = var.product_cache_policy_id
    origin_request_policy_id = var.origin_request_policy_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
  }

  # 4. /api/cart*
  ordered_cache_behavior {
    path_pattern             = "/api/cart*"
    target_origin_id         = "alb-vpc-origin"
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = var.origin_request_policy_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
  }

  # 5. /api/user*
  ordered_cache_behavior {
    path_pattern             = "/api/user*"
    target_origin_id         = "alb-vpc-origin"
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = var.origin_request_policy_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
  }

  # 6. /api/orders*
  ordered_cache_behavior {
    path_pattern             = "/api/orders*"
    target_origin_id         = "alb-vpc-origin"
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = var.origin_request_policy_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
  }

  # 7. /api/debug*
  ordered_cache_behavior {
    path_pattern             = "/api/debug*"
    target_origin_id         = "alb-vpc-origin"
    cache_policy_id          = local.cache_policy_caching_disabled
    origin_request_policy_id = var.origin_request_policy_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["GET", "HEAD"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
  }

  # 8. /api/delay/*
  ordered_cache_behavior {
    path_pattern           = "/api/delay/*"
    target_origin_id       = "alb-vpc-origin"
    cache_policy_id        = local.cache_policy_caching_disabled
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # 9. /api/health*
  ordered_cache_behavior {
    path_pattern           = "/api/health*"
    target_origin_id       = "alb-vpc-origin"
    cache_policy_id        = local.cache_policy_caching_disabled
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
  }

  # 10. /premium/*
  ordered_cache_behavior {
    path_pattern           = "/premium/*"
    target_origin_id       = "s3-origin"
    cache_policy_id        = local.cache_policy_caching_optimized
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    trusted_key_groups     = var.key_group_id != "" ? [var.key_group_id] : []
  }

  # ===========================================================================
  # Default Cache Behavior
  # ===========================================================================
  default_cache_behavior {
    target_origin_id         = "alb-vpc-origin"
    cache_policy_id          = var.page_cache_policy_id
    origin_request_policy_id = var.origin_request_policy_id
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true

    # Staging 可绑定不同的 CloudFront Function 进行测试
    dynamic "function_association" {
      for_each = var.cf_function_arn != "" ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = var.cf_function_arn
      }
    }
  }

  # ===========================================================================
  # 自定义错误页面（与 Production 一致）
  # ===========================================================================
  custom_error_response {
    error_code            = 403
    response_page_path    = "/static/errors/403.html"
    response_code         = 403
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 404
    response_page_path    = "/static/errors/404.html"
    response_code         = 404
    error_caching_min_ttl = 300
  }

  custom_error_response {
    error_code            = 500
    response_page_path    = "/static/errors/500.html"
    response_code         = 500
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 502
    response_page_path    = "/static/errors/502.html"
    response_code         = 502
    error_caching_min_ttl = 60
  }

  # ===========================================================================
  # TLS 证书（与 Production 使用同一 ACM 证书）
  # ===========================================================================
  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, {
    Name = "${var.name}-staging-cloudfront"
    Role = "staging"
  })
}

# -----------------------------------------------------------------------------
# Continuous Deployment Policy
# 将一部分真实流量从 Production 路由到 Staging Distribution 进行验证
# 支持两种分流模式:
#   - SingleWeight: 按权重百分比分流（如 5% 流量到 Staging）
#   - SingleHeader: 按请求 Header 分流（测试人员手动添加 Header）
# -----------------------------------------------------------------------------
resource "aws_cloudfront_continuous_deployment_policy" "main" {
  enabled = true

  staging_distribution_dns_names {
    items    = [aws_cloudfront_distribution.staging.domain_name]
    quantity = 1
  }

  traffic_config {
    type = var.traffic_config_type

    # SingleWeight 模式: 按权重百分比分流
    dynamic "single_weight_config" {
      for_each = var.traffic_config_type == "SingleWeight" ? [1] : []
      content {
        weight = var.staging_traffic_weight

        session_stickiness_config {
          idle_ttl    = 300
          maximum_ttl = 600
        }
      }
    }

    # SingleHeader 模式: 按 Header 值分流
    dynamic "single_header_config" {
      for_each = var.traffic_config_type == "SingleHeader" ? [1] : []
      content {
        header = "aws-cf-cd-staging"
        value  = "true"
      }
    }
  }
}
```

- [ ] **Step 3: 创建 variables.tf — CD 模块输入变量**

Write to `terraform/modules/cloudfront-cd/variables.tf`:

```hcl
# =============================================================================
# CloudFront Continuous Deployment 模块 — 输入变量
# =============================================================================

# -----------------------------------------------------------------------------
# 基础配置
# -----------------------------------------------------------------------------
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

variable "price_class" {
  description = "CloudFront 价格等级"
  type        = string
  default     = "PriceClass_All"
}

# -----------------------------------------------------------------------------
# Production Distribution 引用
# -----------------------------------------------------------------------------
variable "production_distribution_id" {
  description = "Production CloudFront Distribution ID（用于标签和文档引用）"
  type        = string
  default     = ""
}

variable "production_distribution_arn" {
  description = "Production CloudFront Distribution ARN"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Origin 配置（与 Production 共享）
# -----------------------------------------------------------------------------
variable "s3_bucket_regional_domain_name" {
  description = "S3 桶区域域名"
  type        = string
}

variable "alb_dns_name" {
  description = "Internal ALB DNS 名称"
  type        = string
}

variable "oac_id" {
  description = "S3 Origin Access Control ID（共享 Production 的 OAC）"
  type        = string
}

variable "vpc_origin_id" {
  description = "VPC Origin ID（共享 Production 的 VPC Origin）"
  type        = string
}

# -----------------------------------------------------------------------------
# 缓存策略 ID（从 cloudfront 模块传入）
# -----------------------------------------------------------------------------
variable "product_cache_policy_id" {
  description = "ProductCache 自定义缓存策略 ID"
  type        = string
}

variable "page_cache_policy_id" {
  description = "PageCache 自定义缓存策略 ID"
  type        = string
}

variable "origin_request_policy_id" {
  description = "AllViewerExceptHostHeader ORP ID"
  type        = string
}

# -----------------------------------------------------------------------------
# 安全
# -----------------------------------------------------------------------------
variable "acm_certificate_arn" {
  description = "us-east-1 ACM 证书 ARN"
  type        = string
}

variable "waf_web_acl_arn" {
  description = "WAF Web ACL ARN（为空则不关联）"
  type        = string
  default     = ""
}

variable "key_group_id" {
  description = "签名 URL Key Group ID（为空则 /premium/* 不要求签名）"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# CloudFront Function
# -----------------------------------------------------------------------------
variable "cf_function_arn" {
  description = "绑定到 Default Behavior 的 CloudFront Function ARN（为空则不绑定）"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# 流量策略
# -----------------------------------------------------------------------------
variable "traffic_config_type" {
  description = "流量分流模式: SingleWeight (按权重) 或 SingleHeader (按 Header)"
  type        = string
  default     = "SingleWeight"

  validation {
    condition     = contains(["SingleWeight", "SingleHeader"], var.traffic_config_type)
    error_message = "traffic_config_type must be SingleWeight or SingleHeader"
  }
}

variable "staging_traffic_weight" {
  description = "SingleWeight 模式下导入 Staging 的流量百分比 (0.0 ~ 0.15)"
  type        = number
  default     = 0.05
}
```

- [ ] **Step 4: 创建 outputs.tf — CD 模块输出**

Write to `terraform/modules/cloudfront-cd/outputs.tf`:

```hcl
# =============================================================================
# CloudFront Continuous Deployment 模块 — 输出
# =============================================================================

output "staging_distribution_id" {
  description = "Staging CloudFront Distribution ID"
  value       = aws_cloudfront_distribution.staging.id
}

output "staging_distribution_domain" {
  description = "Staging CloudFront Distribution 域名"
  value       = aws_cloudfront_distribution.staging.domain_name
}

output "cd_policy_id" {
  description = "Continuous Deployment Policy ID（传给 Production Distribution）"
  value       = aws_cloudfront_continuous_deployment_policy.main.id
}

output "cd_policy_etag" {
  description = "Continuous Deployment Policy ETag（promote 操作需要）"
  value       = aws_cloudfront_continuous_deployment_policy.main.etag
}
```

---

### Task 15: Root Module 集成 (main.tf)

**目标**: 编写根模块 `terraform/main.tf`，将所有模块串联起来。条件创建通过 `count = var.enable_* ? 1 : 0` 控制。输出关键资源 ID/URL，提供完整的 `terraform.tfvars.example`。

**Files to create:**
- `terraform/main.tf`
- `terraform/outputs.tf`
- `terraform/terraform.tfvars.example`

---

- [ ] **Step 1: 创建 main.tf — 根模块编排**

> **依赖链**: network → (s3 + ec2 + alb 并行) → waf → cloudfront → cloudfront-cd
>
> WAF 必须在 cloudfront 之前创建（cloudfront 需要 WAF ARN）。cloudfront-cd 需要 cloudfront 的输出（缓存策略 ID 等），但 cloudfront 也可选地接收 cloudfront-cd 的输出（CD policy ID）。通过将 `cd_policy_id` 设为可选变量打破循环依赖。

Write to `terraform/main.tf`:

```hcl
# =============================================================================
# CloudFront 全功能演示平台 — 根模块
# 域名: unice.keithyu.cloud | 区域: ap-northeast-1 | Profile: default
# =============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Providers
# 主区域 ap-northeast-1 (东京) — 大部分资源部署于此
# 辅助区域 us-east-1 — WAF Web ACL + ACM 证书（CloudFront 全球服务要求）
# -----------------------------------------------------------------------------
provider "aws" {
  region  = "ap-northeast-1"
  profile = "default"

  default_tags {
    tags = {
      Project     = var.name
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = "default"

  default_tags {
    tags = {
      Project     = var.name
      Environment = "demo"
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Data Sources — 引用已有资源
# -----------------------------------------------------------------------------
data "aws_vpc" "existing" {
  id = var.vpc_id
}

data "aws_route53_zone" "main" {
  name = "keithyu.cloud"
}

# -----------------------------------------------------------------------------
# Module: Network — 安全组（ALB / EC2 / Aurora）
# 始终创建，其他模块依赖安全组
# -----------------------------------------------------------------------------
module "network" {
  source = "./modules/network"

  name   = var.name
  vpc_id = var.vpc_id

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: S3 — 静态内容桶 + OAC 策略 + 错误页面
# 始终创建，CloudFront 和 EC2 都需要
# -----------------------------------------------------------------------------
module "s3" {
  source = "./modules/s3"

  name = var.name

  # CloudFront Distribution ARN 用于 S3 Bucket Policy 限制 OAC 访问
  cloudfront_distribution_arn = var.enable_cloudfront ? module.cloudfront[0].distribution_arn : ""

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: EC2 — Express 应用服务器
# 始终创建，部署在 Private Subnet
# -----------------------------------------------------------------------------
module "ec2" {
  source = "./modules/ec2"

  name              = var.name
  vpc_id            = var.vpc_id
  subnet_id         = var.private_subnet_ids[0]
  ec2_sg_id         = module.network.ec2_sg_id
  key_name          = var.key_name
  instance_type     = var.instance_type
  s3_bucket_name    = module.s3.bucket_name
  enable_cognito    = var.enable_cognito
  enable_aurora     = var.enable_aurora
  signed_url_key_path = var.enable_cloudfront && var.enable_signed_url ? module.cloudfront[0].signed_url_private_key_path : ""

  tags = var.tags

  depends_on = [module.network]
}

# -----------------------------------------------------------------------------
# Module: ALB — Internal Application Load Balancer
# 始终创建，CloudFront VPC Origin 连接到此 ALB
# -----------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  name       = var.name
  vpc_id     = var.vpc_id
  subnet_ids = var.private_subnet_ids
  alb_sg_id  = module.network.alb_sg_id
  ec2_instance_id = module.ec2.instance_id

  tags = var.tags

  depends_on = [module.ec2]
}

# -----------------------------------------------------------------------------
# Module: WAF — Web Application Firewall (us-east-1)
# 条件创建: var.enable_waf
# 必须在 cloudfront 之前创建（cloudfront 需要 WAF ARN）
# -----------------------------------------------------------------------------
module "waf" {
  count  = var.enable_waf ? 1 : 0
  source = "./modules/waf"

  # WAF 必须在 us-east-1
  providers = {
    aws = aws.us_east_1
  }

  name                = var.name
  enable_bot_control  = var.enable_waf_bot_control
  rate_limit          = var.waf_rate_limit
  geo_block_countries = var.waf_geo_block_countries

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: CloudFront — Distribution + Behaviors + Functions + Signed URL
# 条件创建: var.enable_cloudfront
# 依赖: alb (VPC Origin), s3 (OAC), waf (Web ACL)
# -----------------------------------------------------------------------------
module "cloudfront" {
  count  = var.enable_cloudfront ? 1 : 0
  source = "./modules/cloudfront"

  name = var.name

  # S3 源站
  s3_bucket_regional_domain_name = module.s3.bucket_regional_domain_name
  s3_bucket_id                   = module.s3.bucket_id

  # ALB 源站 (VPC Origin)
  alb_dns_name = module.alb.alb_dns_name
  alb_arn      = module.alb.alb_arn

  # 域名与证书
  custom_domain       = var.custom_domain
  acm_certificate_arn = var.acm_certificate_arn
  route53_zone_id     = data.aws_route53_zone.main.zone_id

  # WAF
  waf_web_acl_arn = var.enable_waf ? module.waf[0].web_acl_arn : ""

  # Feature Flags
  enable_signed_url         = var.enable_signed_url
  enable_geo_restriction    = var.enable_geo_restriction
  geo_restriction_type      = var.geo_restriction_type
  geo_restriction_locations = var.geo_restriction_locations
  default_cf_function       = var.default_cf_function

  # Continuous Deployment (可选关联)
  cd_policy_id = var.enable_continuous_deployment ? module.cloudfront_cd[0].cd_policy_id : ""

  # 价格
  price_class = var.price_class

  tags = var.tags

  depends_on = [module.alb, module.s3]
}

# -----------------------------------------------------------------------------
# Module: CloudFront CD — Continuous Deployment (Staging Distribution)
# 条件创建: var.enable_continuous_deployment
# 与 Production 共享 Origin、缓存策略、Function 等资源
# -----------------------------------------------------------------------------
module "cloudfront_cd" {
  count  = var.enable_continuous_deployment ? 1 : 0
  source = "./modules/cloudfront-cd"

  name = var.name

  # Production 引用
  production_distribution_id  = var.enable_cloudfront ? module.cloudfront[0].distribution_id : ""
  production_distribution_arn = var.enable_cloudfront ? module.cloudfront[0].distribution_arn : ""

  # 共享 Origin 配置
  s3_bucket_regional_domain_name = module.s3.bucket_regional_domain_name
  alb_dns_name                   = module.alb.alb_dns_name
  oac_id                         = var.enable_cloudfront ? module.cloudfront[0].oac_id : ""
  vpc_origin_id                  = var.enable_cloudfront ? module.cloudfront[0].vpc_origin_id : ""

  # 共享缓存策略
  product_cache_policy_id  = var.enable_cloudfront ? module.cloudfront[0].product_cache_policy_id : ""
  page_cache_policy_id     = var.enable_cloudfront ? module.cloudfront[0].page_cache_policy_id : ""
  origin_request_policy_id = var.enable_cloudfront ? module.cloudfront[0].origin_request_policy_id : ""

  # 安全
  acm_certificate_arn = var.acm_certificate_arn
  waf_web_acl_arn     = var.enable_waf ? module.waf[0].web_acl_arn : ""
  key_group_id        = var.enable_cloudfront && var.enable_signed_url ? module.cloudfront[0].key_group_id : ""

  # CloudFront Function
  cf_function_arn = var.enable_cloudfront && var.default_cf_function != "none" ? (
    var.default_cf_function == "url-rewrite"  ? module.cloudfront[0].cf_function_url_rewrite_arn :
    var.default_cf_function == "ab-test"      ? module.cloudfront[0].cf_function_ab_test_arn :
    module.cloudfront[0].cf_function_geo_redirect_arn
  ) : ""

  # 流量策略
  traffic_config_type    = var.cd_traffic_config_type
  staging_traffic_weight = var.cd_staging_traffic_weight

  price_class = var.price_class

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: Cognito — User Pool + App Client
# 条件创建: var.enable_cognito
# -----------------------------------------------------------------------------
module "cognito" {
  count  = var.enable_cognito ? 1 : 0
  source = "./modules/cognito"

  name = var.name

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: Database — Aurora Serverless v2 + DynamoDB
# 条件创建: var.enable_aurora
# -----------------------------------------------------------------------------
module "database" {
  count  = var.enable_aurora ? 1 : 0
  source = "./modules/database"

  name      = var.name
  vpc_id    = var.vpc_id
  subnet_ids = var.private_subnet_ids
  db_sg_id  = module.network.db_sg_id

  tags = var.tags

  depends_on = [module.network]
}
```

- [ ] **Step 2: 创建 outputs.tf — 根模块输出**

Write to `terraform/outputs.tf`:

```hcl
# =============================================================================
# 根模块输出 — 关键资源 ID / URL / ARN
# =============================================================================

# -----------------------------------------------------------------------------
# 站点访问
# -----------------------------------------------------------------------------
output "site_url" {
  description = "站点 URL"
  value       = var.enable_cloudfront ? "https://${var.custom_domain}" : "N/A (CloudFront disabled)"
}

output "cloudfront_distribution_id" {
  description = "CloudFront Distribution ID"
  value       = var.enable_cloudfront ? module.cloudfront[0].distribution_id : null
}

output "cloudfront_distribution_domain" {
  description = "CloudFront Distribution 域名 (d1234.cloudfront.net)"
  value       = var.enable_cloudfront ? module.cloudfront[0].distribution_domain : null
}

# -----------------------------------------------------------------------------
# 源站
# -----------------------------------------------------------------------------
output "alb_dns_name" {
  description = "Internal ALB DNS 名称"
  value       = module.alb.alb_dns_name
}

output "ec2_instance_id" {
  description = "EC2 实例 ID"
  value       = module.ec2.instance_id
}

output "s3_bucket_name" {
  description = "S3 静态内容桶名称"
  value       = module.s3.bucket_name
}

# -----------------------------------------------------------------------------
# 安全
# -----------------------------------------------------------------------------
output "waf_web_acl_arn" {
  description = "WAF Web ACL ARN"
  value       = var.enable_waf ? module.waf[0].web_acl_arn : null
}

output "signed_url_private_key_path" {
  description = "签名 URL 私钥本地路径（EC2 user_data 需要此密钥）"
  value       = var.enable_cloudfront && var.enable_signed_url ? module.cloudfront[0].signed_url_private_key_path : null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Continuous Deployment
# -----------------------------------------------------------------------------
output "staging_distribution_id" {
  description = "Staging CloudFront Distribution ID"
  value       = var.enable_continuous_deployment ? module.cloudfront_cd[0].staging_distribution_id : null
}

output "staging_distribution_domain" {
  description = "Staging CloudFront Distribution 域名"
  value       = var.enable_continuous_deployment ? module.cloudfront_cd[0].staging_distribution_domain : null
}

# -----------------------------------------------------------------------------
# 认证
# -----------------------------------------------------------------------------
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = var.enable_cognito ? module.cognito[0].user_pool_id : null
}

# -----------------------------------------------------------------------------
# 数据库
# -----------------------------------------------------------------------------
output "aurora_cluster_endpoint" {
  description = "Aurora Serverless v2 集群端点"
  value       = var.enable_aurora ? module.database[0].cluster_endpoint : null
}

# -----------------------------------------------------------------------------
# 操作提示
# -----------------------------------------------------------------------------
output "next_steps" {
  description = "部署后操作步骤"
  value = <<-EOT

    ========================================
    CloudFront 全功能演示平台 - 部署完成
    ========================================

    1. 上传静态资源到 S3:
       aws s3 sync ./static/ s3://${module.s3.bucket_name}/ --profile default

    2. 验证站点:
       curl -I https://${var.custom_domain}/api/health

    3. 测试 CloudFront Functions:
       # URL 重写
       curl -v https://${var.custom_domain}/products/1
       # Debug 端点查看注入的 header
       curl https://${var.custom_domain}/api/debug | jq

    4. 测试 WAF:
       # 速率限制测试
       for i in $(seq 1 100); do curl -s -o /dev/null -w "%%{http_code}\n" https://${var.custom_domain}/api/health; done

    5. 测试签名 URL:
       # 直接访问 /premium/* 应返回 403
       curl -I https://${var.custom_domain}/premium/test.pdf

    ${var.enable_continuous_deployment ? "6. Continuous Deployment:\n       # Staging 域名: ${module.cloudfront_cd[0].staging_distribution_domain}\n       # 添加 Header 测试: curl -H 'aws-cf-cd-staging: true' https://${var.custom_domain}/" : ""}
  EOT
}
```

- [ ] **Step 3: 创建 terraform.tfvars.example — 完整示例配置**

Write to `terraform/terraform.tfvars.example`:

```hcl
# =============================================================================
# CloudFront 全功能演示平台 — 示例配置
# 复制为 terraform.tfvars 并填写实际值后执行 terraform apply
# =============================================================================

# -----------------------------------------------------------------------------
# 基础配置
# -----------------------------------------------------------------------------
name = "unice"

# -----------------------------------------------------------------------------
# 网络 — 引用现有 VPC
# -----------------------------------------------------------------------------
vpc_id = "vpc-086e15047c7f68e87"

# -----------------------------------------------------------------------------
# EC2
# -----------------------------------------------------------------------------
instance_type = "t4g.small"
key_name      = "keith-secret"

# -----------------------------------------------------------------------------
# 域名与证书
# -----------------------------------------------------------------------------
custom_domain       = "unice.keithyu.cloud"
acm_certificate_arn = "arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2"

# -----------------------------------------------------------------------------
# CloudFront
# -----------------------------------------------------------------------------
price_class       = "PriceClass_All"
default_cf_function = "url-rewrite"   # 可选: url-rewrite, ab-test, geo-redirect, none

# 地理限制
geo_restriction_type      = "blacklist"
geo_restriction_locations = ["KP", "IR"]

# -----------------------------------------------------------------------------
# WAF
# -----------------------------------------------------------------------------
waf_rate_limit          = 2000
waf_geo_block_countries = ["KP", "IR"]

# -----------------------------------------------------------------------------
# Continuous Deployment
# -----------------------------------------------------------------------------
cd_traffic_config_type    = "SingleWeight"   # 可选: SingleWeight, SingleHeader
cd_staging_traffic_weight = 0.05             # 5% 流量到 Staging

# -----------------------------------------------------------------------------
# Feature Flags — 按需开启/关闭各功能模块
# 详见 spec Section 14
# -----------------------------------------------------------------------------
enable_cloudfront            = true
enable_waf                   = true
enable_waf_bot_control       = false   # 额外费用: $10/月 + $1/百万请求
enable_signed_url            = true    # 无额外费用
enable_geo_restriction       = true    # 无额外费用
enable_cognito               = true    # 免费层 50,000 MAU
enable_aurora                = true    # 最低约 $43/月 (0.5 ACU)
enable_continuous_deployment = false   # Staging 分发请求单独计费

# -----------------------------------------------------------------------------
# 资源标签
# -----------------------------------------------------------------------------
tags = {
  Owner       = "Keith"
  Purpose     = "CloudFront Demo Platform"
  CostCenter  = "SA-Demo"
}
```

- [ ] **Step 4: 创建 keys/.gitignore — 防止私钥泄露**

```bash
mkdir -p /root/keith-space/2026-project/longqi-cloudfront/terraform/keys
```

Write to `terraform/keys/.gitignore`:

```
# 签名 URL RSA 私钥 — 绝不可提交到 Git
*.pem
```

- [ ] **Step 5: 验证模块间依赖关系**

```
根模块依赖图:

  network ─────────────┬──────────────────┐
     │                 │                  │
     v                 v                  v
    ec2              alb              database (条件)
     │                │
     └──────┬─────────┘
            │
            v
    waf (us-east-1, 条件) ─────┐
                               │
                               v
                         cloudfront (条件) ──── cloudfront_cd (条件)
                               │                      │
                               └──── cd_policy_id ─────┘
                                    (可选反向引用)

  cognito (条件) — 独立，无模块间依赖
```

- [ ] **Step 6: 运行 Terraform 格式检查和验证**

```bash
cd /root/keith-space/2026-project/longqi-cloudfront/terraform

# 格式化所有 .tf 文件
terraform fmt -recursive

# 初始化（下载 provider）
terraform init

# 语法验证
terraform validate

# 查看计划（不实际创建资源）
terraform plan -var-file=terraform.tfvars
```

- [ ] **Step 7: 确认 Feature Flag 控制表**

| 变量 | 默认值 | 控制的模块 | 月费用估算 |
|---|---|---|---|
| `enable_cloudfront` | `true` | cloudfront | 按请求量 |
| `enable_waf` | `true` | waf | ~$8/月 (ACL + 规则) |
| `enable_waf_bot_control` | `false` | waf (Bot Control 规则) | +$10/月 + $1/百万请求 |
| `enable_signed_url` | `true` | cloudfront (Key Group + RSA 密钥) | 无 |
| `enable_geo_restriction` | `true` | cloudfront (geo_restriction) | 无 |
| `enable_cognito` | `true` | cognito | 免费层 50K MAU |
| `enable_aurora` | `true` | database | ~$43/月 (0.5 ACU) |
| `enable_continuous_deployment` | `false` | cloudfront-cd | 与 Production 相同 |
