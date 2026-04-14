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
    var.default_cf_function == "url-rewrite" ? aws_cloudfront_function.url_rewrite.arn :
    var.default_cf_function == "ab-test" ? aws_cloudfront_function.ab_test.arn :
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
