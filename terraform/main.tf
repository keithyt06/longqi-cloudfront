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

  name        = var.name
  bucket_name = var.s3_bucket_name

  # CloudFront Distribution ARN 用于 S3 Bucket Policy 限制 OAC 访问
  # 初次 apply 传空字符串（避免 S3↔CloudFront 循环依赖），CloudFront 创建后由下方独立资源设置
  cloudfront_distribution_arn = ""

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Module: EC2 — Express 应用服务器
# 始终创建，部署在 Private Subnet
# -----------------------------------------------------------------------------
module "ec2" {
  source = "./modules/ec2"

  name               = var.name
  instance_type      = var.instance_type
  subnet_id          = var.private_subnet_ids[0]
  security_group_ids = [module.network.ec2_security_group_id]
  key_name           = var.key_name
  root_volume_size   = var.root_volume_size
  region             = var.region
  tags               = var.tags

  # 应用环境变量（传入 user_data.sh 模板）
  db_host               = var.enable_aurora ? module.database[0].aurora_endpoint : ""
  db_name               = "unice"
  db_user               = "unice_admin"
  db_password           = var.db_password
  cognito_user_pool_id  = var.enable_cognito ? module.cognito[0].user_pool_id : ""
  cognito_client_id     = var.enable_cognito ? module.cognito[0].user_pool_client_id : ""
  cognito_user_pool_arn = var.enable_cognito ? module.cognito[0].user_pool_arn : ""
  enable_cognito        = var.enable_cognito
  dynamodb_table_name   = var.enable_aurora ? module.database[0].dynamodb_table_name : "unice-trace-mapping"
  dynamodb_table_arn    = var.enable_aurora ? module.database[0].dynamodb_table_arn : ""
  s3_bucket_name        = var.s3_bucket_name
  s3_bucket_arn         = module.s3.bucket_arn

  depends_on = [module.network]
}

# -----------------------------------------------------------------------------
# Module: ALB — Internal Application Load Balancer
# 始终创建，CloudFront VPC Origin 连接到此 ALB
# -----------------------------------------------------------------------------
module "alb" {
  source = "./modules/alb"

  name               = var.name
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.network.alb_security_group_id]
  target_instance_id = module.ec2.instance_id

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

  # Continuous Deployment — 传空字符串避免 CloudFront↔CD 循环依赖
  # CD 策略关联在 Staging Distribution 创建后通过 Console/CLI 手动完成
  cd_policy_id = ""

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
    var.default_cf_function == "url-rewrite" ? module.cloudfront[0].cf_function_url_rewrite_arn :
    var.default_cf_function == "ab-test" ? module.cloudfront[0].cf_function_ab_test_arn :
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

  name                 = var.name
  vpc_id               = var.vpc_id
  region               = var.region
  private_subnet_ids   = var.private_subnet_ids
  db_security_group_id = module.network.db_security_group_id
  db_password          = var.db_password
  enable_aurora        = var.enable_aurora

  tags = var.tags

  depends_on = [module.network]
}

# -----------------------------------------------------------------------------
# Module: Tag-Based Invalidation — Lambda@Edge + DynamoDB tag→URL 映射
# 条件创建: var.enable_tag_invalidation
# 依赖: cloudfront (Distribution ID/ARN)
# -----------------------------------------------------------------------------
module "tag_invalidation" {
  count  = var.enable_tag_invalidation && var.enable_cloudfront ? 1 : 0
  source = "./modules/tag-invalidation"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  name                    = var.name
  distribution_id         = module.cloudfront[0].distribution_id
  distribution_arn        = module.cloudfront[0].distribution_arn
  dynamodb_table_name     = "${var.name}-cache-tags"
  tag_header_name         = "cache-tag"
  tag_delimiter           = ","
  tag_ttl_seconds         = 86400
  enable_step_functions   = var.enable_tag_invalidation_step_functions
  invalidation_batch_size = 3000

  tags = var.tags
}

# -----------------------------------------------------------------------------
# S3 OAC Bucket Policy — 独立资源，避免 S3↔CloudFront 循环依赖
# CloudFront 创建后自动设置 OAC 策略，限制仅指定 Distribution 可访问 S3
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "s3_oac" {
  count = var.enable_cloudfront ? 1 : 0

  statement {
    sid       = "AllowCloudFrontOAC"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${module.s3.bucket_arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [module.cloudfront[0].distribution_arn]
    }
  }
}

resource "aws_s3_bucket_policy" "oac" {
  count  = var.enable_cloudfront ? 1 : 0
  bucket = module.s3.bucket_id
  policy = data.aws_iam_policy_document.s3_oac[0].json
}
