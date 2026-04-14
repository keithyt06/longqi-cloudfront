# =============================================================================
# S3 模块 - 静态资源桶
# =============================================================================
# - 存储 CSS/JS/图片/字体等静态资源
# - 存储自定义错误页面 (/static/errors/*.html)
# - 存储签名 URL 保护的会员内容 (/premium/*)
# - 通过 CloudFront OAC 访问，禁止公共直接访问
# =============================================================================

# S3 桶
resource "aws_s3_bucket" "static" {
  bucket = var.bucket_name

  tags = merge(var.tags, {
    Name = "${var.name}-static"
  })
}

# 启用版本控制（便于静态资源回滚）
resource "aws_s3_bucket_versioning" "static" {
  bucket = aws_s3_bucket.static.id

  versioning_configuration {
    status = "Enabled"
  }
}

# 阻止所有公共访问（仅通过 CloudFront OAC 访问）
resource "aws_s3_bucket_public_access_block" "static" {
  bucket = aws_s3_bucket.static.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# -----------------------------------------------------------------------------
# OAC Bucket Policy - 仅允许 CloudFront Distribution 通过 OAC 访问
# 条件创建：cloudfront_distribution_arn 为空时不创建（Part 2 回填）
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "oac" {
  count = var.cloudfront_distribution_arn != "" ? 1 : 0

  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.static.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [var.cloudfront_distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "oac" {
  count  = var.cloudfront_distribution_arn != "" ? 1 : 0
  bucket = aws_s3_bucket.static.id
  policy = data.aws_iam_policy_document.oac[0].json
}

# S3 桶 CORS 配置（允许 CloudFront 域名跨域请求字体等资源）
resource "aws_s3_bucket_cors_configuration" "static" {
  bucket = aws_s3_bucket.static.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD"]
    allowed_origins = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}
