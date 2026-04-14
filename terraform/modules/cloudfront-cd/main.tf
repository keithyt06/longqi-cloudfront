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
