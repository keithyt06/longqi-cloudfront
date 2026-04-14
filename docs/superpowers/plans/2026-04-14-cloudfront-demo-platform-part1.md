# CloudFront 全功能演示平台 - 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个参考 unice.com 的功能性电商模拟网站，作为 CloudFront 全栈功能（多源路由、缓存策略、Functions、WAF Bot Control、VPC Origin、Continuous Deployment、签名 URL 等）的演示和测试平台。

**Architecture:** S3（静态）+ EC2 Express（动态 API）双源，CloudFront 统一入口，Internal ALB 通过 VPC Origin 连接，全内网架构。Cognito 做用户认证，DynamoDB 做 UUID 追踪映射，Aurora Serverless v2 存商品/订单数据。

**Tech Stack:** Terraform, AWS CloudFront, ALB, EC2, S3, WAF, Cognito, Aurora Serverless v2, DynamoDB, Node.js Express, EJS

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

---

## 文件结构总览 (Part 1)

```
terraform/
├── main.tf                              # Dual-region Provider (ap-northeast-1 + us-east-1)、data source、模块编排
├── variables.tf                         # 所有变量 + enable_* feature flags（含 Part 2 变量）
├── outputs.tf                           # 根模块输出（网络、S3、数据库、认证、计算、负载均衡）
├── terraform.tfvars.example             # 配置示例（含已有资源 ID、feature flag 开关）
├── modules/
│   ├── network/                         # 安全组：VPC Origin SG / ALB SG / EC2 SG / DB SG
│   │   ├── main.tf                      #   链式最小权限：VPC Origin → ALB → EC2 → DB
│   │   ├── variables.tf                 #   输入：name, vpc_id, tags
│   │   └── outputs.tf                   #   输出：4 个安全组 ID
│   ├── s3/                              # S3 静态资源桶
│   │   ├── main.tf                      #   桶 + 版本控制 + 公共访问阻止 + OAC Bucket Policy（条件创建）
│   │   ├── variables.tf                 #   输入：bucket_name, cloudfront_distribution_arn
│   │   └── outputs.tf                   #   输出：bucket_id, bucket_arn, bucket_regional_domain_name
│   ├── database/                        # Aurora Serverless v2 + DynamoDB + VPC Endpoints
│   │   ├── main.tf                      #   Aurora 集群/实例（条件创建）、DynamoDB trace-mapping 表、Gateway Endpoints
│   │   ├── variables.tf                 #   输入：enable_aurora, db_password, private_subnet_ids, db_security_group_id
│   │   └── outputs.tf                   #   输出：aurora_endpoint, dynamodb_table_name/arn
│   ├── cognito/                         # Cognito 用户认证
│   │   ├── main.tf                      #   User Pool (unice-user-pool) + App Client (unice-web-client, 无 secret)
│   │   ├── variables.tf                 #   输入：name, tags
│   │   └── outputs.tf                   #   输出：user_pool_id, user_pool_arn, user_pool_client_id
│   ├── ec2/                             # EC2 应用服务器
│   │   ├── main.tf                      #   EC2 实例 + IAM Role/Profile（DynamoDB/S3/Cognito 权限）
│   │   ├── variables.tf                 #   输入：instance_type, subnet_id, 各服务端点/ARN
│   │   ├── outputs.tf                   #   输出：instance_id, instance_private_ip
│   │   └── user_data.sh                 #   启动脚本：Node.js 20 + pm2 + Express placeholder app
│   └── alb/                             # Internal Application Load Balancer
│       ├── main.tf                      #   Internal ALB + Target Group (port 3000) + HTTP Listener
│       ├── variables.tf                 #   输入：private_subnet_ids, target_instance_id
│       └── outputs.tf                   #   输出：alb_arn, alb_dns_name, alb_zone_id
│
│   # ── Part 2 模块（本计划不包含）──
│   ├── cloudfront/                      # [Part 2] Distribution + Behaviors + Functions + OAC + VPC Origin
│   ├── cloudfront-cd/                   # [Part 2] Continuous Deployment (Staging Distribution)
│   └── waf/                             # [Part 2] WAF Web ACL + Bot Control (us-east-1)
└── functions/                           # [Part 2] CloudFront Functions JS 文件
    ├── cf-url-rewrite.js
    ├── cf-ab-test.js
    └── cf-geo-redirect.js
```

---

## Task 1: Terraform 项目脚手架 + Network 模块

创建 Terraform 根文件和 Network 模块。根文件定义 dual-region provider、所有变量（含 Part 2 feature flags）、所有输出。Network 模块创建 4 个安全组，形成 VPC Origin → ALB → EC2 → DB 的链式信任关系。

### Step 1.1: 创建 `terraform/main.tf`

- [ ] 创建文件 `terraform/main.tf`，包含 terraform block、dual provider、所有模块编排

```hcl
# =============================================================================
# CloudFront 全功能演示平台 - Main Configuration
# =============================================================================
# 架构：CloudFront → VPC Origin → Internal ALB → EC2 Express
# 区域：ap-northeast-1 (主) + us-east-1 (WAF/ACM)
# =============================================================================

terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0.0"
    }
  }
}

# 主区域 Provider（东京）
provider "aws" {
  region  = var.region
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}

# us-east-1 Provider（WAF + CloudFront ACM 证书必须在此区域）
provider "aws" {
  alias   = "us_east_1"
  region  = "us-east-1"
  profile = var.aws_profile

  default_tags {
    tags = var.tags
  }
}

# =============================================================================
# Network 模块 - 安全组
# =============================================================================
module "network" {
  source = "./modules/network"

  name   = var.name
  vpc_id = var.vpc_id
  tags   = var.tags
}

# =============================================================================
# S3 模块 - 静态资源桶
# =============================================================================
module "s3" {
  source = "./modules/s3"

  name                        = var.name
  bucket_name                 = var.s3_bucket_name
  cloudfront_distribution_arn = ""  # Part 2: 由 CloudFront 模块输出后回填
  tags                        = var.tags
}

# =============================================================================
# Database 模块 - Aurora Serverless v2 + DynamoDB + VPC Endpoints
# =============================================================================
module "database" {
  source = "./modules/database"

  name                 = var.name
  vpc_id               = var.vpc_id
  region               = var.region
  private_subnet_ids   = var.private_subnet_ids
  db_security_group_id = module.network.db_security_group_id
  db_password          = var.db_password
  enable_aurora        = var.enable_aurora
  tags                 = var.tags
}

# =============================================================================
# Cognito 模块 - 用户认证（条件创建）
# =============================================================================
module "cognito" {
  count  = var.enable_cognito ? 1 : 0
  source = "./modules/cognito"

  name = var.name
  tags = var.tags
}

# =============================================================================
# EC2 模块 - Express 应用服务器
# =============================================================================
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
  db_host              = module.database.aurora_endpoint
  db_name              = "unice"
  db_user              = "unice_admin"
  db_password          = var.db_password
  cognito_user_pool_id = var.enable_cognito ? module.cognito[0].user_pool_id : ""
  cognito_client_id    = var.enable_cognito ? module.cognito[0].user_pool_client_id : ""
  cognito_user_pool_arn = var.enable_cognito ? module.cognito[0].user_pool_arn : ""
  dynamodb_table_name  = module.database.dynamodb_table_name
  dynamodb_table_arn   = module.database.dynamodb_table_arn
  s3_bucket_name       = var.s3_bucket_name
  s3_bucket_arn        = module.s3.bucket_arn
}

# =============================================================================
# ALB 模块 - Internal Application Load Balancer
# =============================================================================
module "alb" {
  source = "./modules/alb"

  name               = var.name
  vpc_id             = var.vpc_id
  private_subnet_ids = var.private_subnet_ids
  security_group_ids = [module.network.alb_security_group_id]
  target_instance_id = module.ec2.instance_id
  tags               = var.tags
}

# =============================================================================
# Part 2 模块占位（CloudFront / WAF / Continuous Deployment）
# =============================================================================
# module "waf" {
#   count  = var.enable_waf ? 1 : 0
#   source = "./modules/waf"
#   providers = { aws = aws.us_east_1 }
#   ...
# }
#
# module "cloudfront" {
#   source = "./modules/cloudfront"
#   ...
# }
#
# module "cloudfront_cd" {
#   count  = var.enable_continuous_deployment ? 1 : 0
#   source = "./modules/cloudfront-cd"
#   ...
# }
```

### Step 1.2: 创建 `terraform/variables.tf`

- [ ] 创建文件 `terraform/variables.tf`，包含所有变量定义（含 Part 2 feature flags）

```hcl
# =============================================================================
# General
# =============================================================================
variable "name" {
  description = "资源名称前缀"
  type        = string
  default     = "unice-demo"
}

variable "region" {
  description = "AWS 主区域"
  type        = string
  default     = "ap-northeast-1"
}

variable "aws_profile" {
  description = "AWS CLI profile 名称"
  type        = string
  default     = "default"
}

variable "tags" {
  description = "所有资源的公共标签"
  type        = map(string)
  default     = {}
}

# =============================================================================
# Network
# =============================================================================
variable "vpc_id" {
  description = "现有 VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet ID 列表（至少 2 个，分布在不同 AZ，用于 ALB / EC2 / Aurora）"
  type        = list(string)
}

# =============================================================================
# EC2
# =============================================================================
variable "instance_type" {
  description = "EC2 实例类型"
  type        = string
  default     = "t3.medium"
}

variable "root_volume_size" {
  description = "EC2 根卷大小 (GB)"
  type        = number
  default     = 20
}

variable "key_name" {
  description = "SSH 密钥对名称"
  type        = string
  default     = "keith-secret"
}

# =============================================================================
# Database
# =============================================================================
variable "db_password" {
  description = "Aurora PostgreSQL master 密码"
  type        = string
  sensitive   = true
}

# =============================================================================
# S3
# =============================================================================
variable "s3_bucket_name" {
  description = "S3 静态资源桶名称（全局唯一）"
  type        = string
}

# =============================================================================
# CloudFront（Part 2 使用，变量预定义）
# =============================================================================
variable "custom_domain" {
  description = "CloudFront 自定义域名 (CNAME)"
  type        = string
  default     = "unice.keithyu.cloud"
}

variable "acm_certificate_arn_us_east_1" {
  description = "us-east-1 的 ACM 通配符证书 ARN（用于 CloudFront）"
  type        = string
  default     = ""
}

variable "route53_zone_name" {
  description = "Route53 托管区域名称"
  type        = string
  default     = "keithyu.cloud"
}

variable "cloudfront_price_class" {
  description = "CloudFront 价格等级"
  type        = string
  default     = "PriceClass_200"
}

# =============================================================================
# WAF（Part 2 使用，变量预定义）
# =============================================================================
variable "waf_rate_limit" {
  description = "WAF 速率限制：同一 IP 每 5 分钟最大请求数"
  type        = number
  default     = 2000
}

# =============================================================================
# Feature Flags
# =============================================================================
variable "enable_cloudfront" {
  description = "启用 CloudFront Distribution"
  type        = bool
  default     = true
}

variable "enable_waf" {
  description = "启用 WAF 基础规则（Common/Bad Inputs/Rate Limit/IP Reputation）"
  type        = bool
  default     = true
}

variable "enable_waf_bot_control" {
  description = "启用 WAF Bot Control Targeted + JS SDK（额外费用 $10/月 + $1/百万请求）"
  type        = bool
  default     = false
}

variable "enable_signed_url" {
  description = "启用签名 URL/Cookie（Trusted Key Group）"
  type        = bool
  default     = true
}

variable "enable_geo_restriction" {
  description = "启用地理限制"
  type        = bool
  default     = true
}

variable "enable_cognito" {
  description = "启用 Cognito User Pool 用户认证"
  type        = bool
  default     = true
}

variable "enable_aurora" {
  description = "启用 Aurora Serverless v2 PostgreSQL（最低约 $43/月）"
  type        = bool
  default     = true
}

variable "enable_continuous_deployment" {
  description = "启用 CloudFront Continuous Deployment（Staging 分发，有额外费用）"
  type        = bool
  default     = false
}

variable "enable_tag_invalidation" {
  description = "启用基于标签的缓存失效（Lambda@Edge + DynamoDB 映射 + 可选 Step Functions）"
  type        = bool
  default     = false
}

variable "enable_tag_invalidation_step_functions" {
  description = "启用 Step Functions 编排分批失效（URL 数量可能超过 3000 时推荐开启）"
  type        = bool
  default     = false
}
```

### Step 1.3: 创建 `terraform/outputs.tf`

- [ ] 创建文件 `terraform/outputs.tf`，包含所有根模块输出

```hcl
# =============================================================================
# Network
# =============================================================================
output "vpc_origin_security_group_id" {
  description = "VPC Origin 安全组 ID（Part 2 CloudFront 模块使用）"
  value       = module.network.vpc_origin_security_group_id
}

output "alb_security_group_id" {
  description = "ALB 安全组 ID"
  value       = module.network.alb_security_group_id
}

output "ec2_security_group_id" {
  description = "EC2 安全组 ID"
  value       = module.network.ec2_security_group_id
}

output "db_security_group_id" {
  description = "数据库安全组 ID"
  value       = module.network.db_security_group_id
}

# =============================================================================
# S3
# =============================================================================
output "s3_bucket_id" {
  description = "S3 静态资源桶 ID"
  value       = module.s3.bucket_id
}

output "s3_bucket_arn" {
  description = "S3 静态资源桶 ARN"
  value       = module.s3.bucket_arn
}

output "s3_bucket_regional_domain_name" {
  description = "S3 桶的区域域名（CloudFront Origin 使用）"
  value       = module.s3.bucket_regional_domain_name
}

# =============================================================================
# Database
# =============================================================================
output "aurora_endpoint" {
  description = "Aurora 写入端点"
  value       = module.database.aurora_endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora 只读端点"
  value       = module.database.aurora_reader_endpoint
}

output "dynamodb_table_name" {
  description = "DynamoDB UUID 映射表名称"
  value       = module.database.dynamodb_table_name
}

# =============================================================================
# Cognito
# =============================================================================
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = var.enable_cognito ? module.cognito[0].user_pool_id : null
}

output "cognito_user_pool_client_id" {
  description = "Cognito App Client ID"
  value       = var.enable_cognito ? module.cognito[0].user_pool_client_id : null
}

# =============================================================================
# EC2
# =============================================================================
output "ec2_instance_id" {
  description = "EC2 实例 ID"
  value       = module.ec2.instance_id
}

output "ec2_private_ip" {
  description = "EC2 实例内网 IP"
  value       = module.ec2.instance_private_ip
}

# =============================================================================
# ALB
# =============================================================================
output "alb_dns_name" {
  description = "Internal ALB DNS 名称（Part 2 CloudFront Origin 使用）"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "ALB Hosted Zone ID"
  value       = module.alb.alb_zone_id
}
```

### Step 1.4: 创建 `terraform/terraform.tfvars.example`

- [ ] 创建文件 `terraform/terraform.tfvars.example`，包含配置示例和说明

```hcl
# =============================================================================
# CloudFront 全功能演示平台 - 配置文件
# =============================================================================
# 使用方法:
#   1. cp terraform.tfvars.example terraform.tfvars
#   2. 修改标记 "CHANGE_ME" 的值
#   3. terraform init && terraform plan && terraform apply
# =============================================================================

# Region & Profile
region      = "ap-northeast-1"
aws_profile = "default"

# 资源名称前缀
name = "unice-demo"

# =============================================================================
# 网络 - 现有 VPC（已有 NAT Gateway 供 EC2 访问外网）
# =============================================================================
vpc_id = "vpc-086e15047c7f68e87"

# Private Subnet（至少 2 个不同 AZ，用于 Internal ALB / EC2 / Aurora）
# 查询命令：
#   aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-086e15047c7f68e87" \
#     --query "Subnets[?MapPublicIpOnLaunch==\`false\`].[SubnetId,AvailabilityZone]" \
#     --output table --region ap-northeast-1
private_subnet_ids = [
  "CHANGE_ME",  # ap-northeast-1a
  "CHANGE_ME"   # ap-northeast-1c
]

# =============================================================================
# EC2
# =============================================================================
instance_type    = "t3.medium"   # 2 vCPU, 4 GB RAM - 演示环境足够
root_volume_size = 20
key_name         = "keith-secret"

# =============================================================================
# Database
# =============================================================================
db_password = "CHANGE_ME"  # Aurora PostgreSQL master 密码

# =============================================================================
# S3
# =============================================================================
s3_bucket_name = "unice-static-keithyu-tokyo"  # 全局唯一

# =============================================================================
# CloudFront（Part 2 配置）
# =============================================================================
custom_domain                 = "unice.keithyu.cloud"
acm_certificate_arn_us_east_1 = "arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2"
route53_zone_name             = "keithyu.cloud"
cloudfront_price_class        = "PriceClass_200"

# =============================================================================
# Feature Flags
# =============================================================================
enable_cloudfront            = true
enable_waf                   = true
enable_waf_bot_control       = false   # 额外费用 $10/月
enable_signed_url            = true
enable_geo_restriction       = true
enable_cognito               = true
enable_aurora                = true
enable_continuous_deployment = false   # Staging 分发有额外费用
enable_tag_invalidation                = false   # Lambda@Edge + DynamoDB 标签缓存失效
enable_tag_invalidation_step_functions = false   # 大规模失效时启用 Step Functions

# =============================================================================
# Tags
# =============================================================================
tags = {
  Environment = "demo"
  Project     = "unice-cloudfront-demo"
  ManagedBy   = "terraform"
  Owner       = "Keith"
}
```

### Step 1.5: 创建 `terraform/modules/network/main.tf`

- [ ] 创建文件 `terraform/modules/network/main.tf`，包含 4 个安全组及链式规则

```hcl
# =============================================================================
# Network 模块 - 安全组
# =============================================================================
# 链式最小权限:
#   CloudFront VPC Origin ENI (vpc_origin SG)
#     → Internal ALB (alb SG, 入站仅 vpc_origin port 80)
#       → EC2 Express (ec2 SG, 入站仅 alb port 3000)
#         → Aurora PostgreSQL (db SG, 入站仅 ec2 port 5432)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. VPC Origin 安全组 - 绑定到 CloudFront VPC Origin 创建的 ENI
# -----------------------------------------------------------------------------
resource "aws_security_group" "vpc_origin" {
  name        = "${var.name}-vpc-origin-sg"
  description = "Security group for CloudFront VPC Origin ENIs"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-vpc-origin-sg"
  })
}

# VPC Origin ENI → ALB (出站到 ALB 安全组 HTTP 80)
resource "aws_security_group_rule" "vpc_origin_egress_alb" {
  type                     = "egress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.vpc_origin.id
  description              = "Allow HTTP to Internal ALB"
}

# -----------------------------------------------------------------------------
# 2. ALB 安全组 - Internal ALB，仅接受 VPC Origin 流量
# -----------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "Security group for Internal ALB - VPC Origin only"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-alb-sg"
  })
}

# 入站：仅允许来自 VPC Origin 安全组的 HTTP 80
resource "aws_security_group_rule" "alb_ingress_vpc_origin" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.vpc_origin.id
  security_group_id        = aws_security_group.alb.id
  description              = "Allow HTTP from CloudFront VPC Origin"
}

# 出站：允许到 EC2 安全组 port 3000（ALB → EC2 转发）
resource "aws_security_group_rule" "alb_egress_ec2" {
  type                     = "egress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2.id
  security_group_id        = aws_security_group.alb.id
  description              = "Allow traffic to EC2 Express on port 3000"
}

# -----------------------------------------------------------------------------
# 3. EC2 安全组 - Express 应用，仅接受 ALB 转发
# -----------------------------------------------------------------------------
resource "aws_security_group" "ec2" {
  name        = "${var.name}-ec2-sg"
  description = "Security group for EC2 Express instance"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-ec2-sg"
  })
}

# 入站：仅允许来自 ALB 安全组的 HTTP 3000（Express 端口）
resource "aws_security_group_rule" "ec2_ingress_alb" {
  type                     = "ingress"
  from_port                = 3000
  to_port                  = 3000
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ec2.id
  description              = "Allow HTTP from ALB on port 3000"
}

# 出站：允许所有（EC2 需要访问 NAT Gateway、VPC Endpoints、Aurora 等）
resource "aws_security_group_rule" "ec2_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.ec2.id
  description       = "Allow all outbound (NAT Gateway, VPC Endpoints, Aurora)"
}

# -----------------------------------------------------------------------------
# 4. DB 安全组 - Aurora PostgreSQL，仅接受 EC2 连接
# -----------------------------------------------------------------------------
resource "aws_security_group" "db" {
  name        = "${var.name}-db-sg"
  description = "Security group for Aurora Serverless v2 PostgreSQL"
  vpc_id      = var.vpc_id

  tags = merge(var.tags, {
    Name = "${var.name}-db-sg"
  })
}

# 入站：仅允许来自 EC2 安全组的 PostgreSQL 5432
resource "aws_security_group_rule" "db_ingress_ec2" {
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.ec2.id
  security_group_id        = aws_security_group.db.id
  description              = "Allow PostgreSQL from EC2"
}

# 出站：无（数据库不需要主动外联）
# AWS 安全组默认无出站规则时会拒绝所有出站，但 Aurora 作为托管服务不需要出站
```

### Step 1.6: 创建 `terraform/modules/network/variables.tf`

- [ ] 创建文件 `terraform/modules/network/variables.tf`

```hcl
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
```

### Step 1.7: 创建 `terraform/modules/network/outputs.tf`

- [ ] 创建文件 `terraform/modules/network/outputs.tf`

```hcl
output "vpc_origin_security_group_id" {
  description = "VPC Origin 安全组 ID（绑定到 CloudFront VPC Origin ENI）"
  value       = aws_security_group.vpc_origin.id
}

output "alb_security_group_id" {
  description = "ALB 安全组 ID"
  value       = aws_security_group.alb.id
}

output "ec2_security_group_id" {
  description = "EC2 安全组 ID"
  value       = aws_security_group.ec2.id
}

output "db_security_group_id" {
  description = "数据库安全组 ID"
  value       = aws_security_group.db.id
}
```

---

## Task 2: S3 模块

创建 S3 静态资源桶，启用版本控制，阻止公共访问，配置 OAC Bucket Policy（条件创建，Part 2 CloudFront 模块提供 distribution ARN 后生效）。

### Step 2.1: 创建 `terraform/modules/s3/main.tf`

- [ ] 创建文件 `terraform/modules/s3/main.tf`

```hcl
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
    sid     = "AllowCloudFrontOAC"
    effect  = "Allow"
    actions = ["s3:GetObject"]
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
```

### Step 2.2: 创建 `terraform/modules/s3/variables.tf`

- [ ] 创建文件 `terraform/modules/s3/variables.tf`

```hcl
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "bucket_name" {
  description = "S3 桶名称（全局唯一）"
  type        = string
}

variable "cloudfront_distribution_arn" {
  description = "CloudFront Distribution ARN（用于 OAC Bucket Policy，为空则不创建策略）"
  type        = string
  default     = ""
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
```

### Step 2.3: 创建 `terraform/modules/s3/outputs.tf`

- [ ] 创建文件 `terraform/modules/s3/outputs.tf`

```hcl
output "bucket_id" {
  description = "S3 桶 ID"
  value       = aws_s3_bucket.static.id
}

output "bucket_arn" {
  description = "S3 桶 ARN"
  value       = aws_s3_bucket.static.arn
}

output "bucket_regional_domain_name" {
  description = "S3 桶区域域名（CloudFront S3 Origin 使用）"
  value       = aws_s3_bucket.static.bucket_regional_domain_name
}
```

---

## Task 3: Database 模块

创建 Aurora Serverless v2 PostgreSQL 集群（条件创建）、DynamoDB UUID 映射表（始终创建）、VPC Gateway Endpoints（DynamoDB + S3）。

### Step 3.1: 创建 `terraform/modules/database/main.tf`

- [ ] 创建文件 `terraform/modules/database/main.tf`

```hcl
# =============================================================================
# Database 模块
# =============================================================================
# 1. Aurora Serverless v2 PostgreSQL - 商品/订单数据（条件创建）
# 2. DynamoDB - UUID 追踪映射表（始终创建）
# 3. VPC Gateway Endpoints - DynamoDB + S3（始终创建，流量不出 VPC）
# =============================================================================

# ─── 查询 VPC 路由表（用于 Gateway Endpoints）──────────────────────────────
data "aws_route_tables" "vpc" {
  vpc_id = var.vpc_id
}

# =============================================================================
# 1. Aurora Serverless v2 PostgreSQL
# =============================================================================

# DB 子网组（Aurora 要求至少 2 个 AZ 的子网）
resource "aws_db_subnet_group" "aurora" {
  count = var.enable_aurora ? 1 : 0

  name       = "${var.name}-aurora-subnet-group"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, {
    Name = "${var.name}-aurora-subnet-group"
  })
}

# 集群参数组
resource "aws_rds_cluster_parameter_group" "aurora" {
  count = var.enable_aurora ? 1 : 0

  family = "aurora-postgresql16"
  name   = "${var.name}-aurora-pg16"

  # 慢查询日志：记录超过 1 秒的查询
  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  tags = merge(var.tags, {
    Name = "${var.name}-aurora-pg16"
  })
}

# Aurora 集群
resource "aws_rds_cluster" "aurora" {
  count = var.enable_aurora ? 1 : 0

  cluster_identifier = "${var.name}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned"
  engine_version     = "16.4"

  database_name   = "unice"
  master_username = "unice_admin"
  master_password = var.db_password

  db_subnet_group_name            = aws_db_subnet_group.aurora[0].name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora[0].name
  vpc_security_group_ids          = [var.db_security_group_id]

  # Serverless v2 容量配置：0.5 ACU (最小) ~ 2 ACU (最大)
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 2
  }

  # 演示环境配置
  skip_final_snapshot = true
  apply_immediately   = true

  tags = merge(var.tags, {
    Name = "${var.name}-aurora"
  })
}

# Aurora Serverless v2 实例
resource "aws_rds_cluster_instance" "aurora" {
  count = var.enable_aurora ? 1 : 0

  identifier         = "${var.name}-aurora-instance-1"
  cluster_identifier = aws_rds_cluster.aurora[0].id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora[0].engine
  engine_version     = aws_rds_cluster.aurora[0].engine_version

  tags = merge(var.tags, {
    Name = "${var.name}-aurora-instance-1"
  })
}

# =============================================================================
# 2. DynamoDB - UUID 追踪映射表
# =============================================================================
# 用途：将 Cognito 用户 ID 与 UUID (x-trace-id) 绑定，实现跨设备统一追踪
# PK = cognito_user_id, GSI = trace_id-index (通过 UUID 反查用户)

resource "aws_dynamodb_table" "trace_mapping" {
  name         = "unice-trace-mapping"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "cognito_user_id"

  attribute {
    name = "cognito_user_id"
    type = "S"
  }

  attribute {
    name = "trace_id"
    type = "S"
  }

  # GSI: 通过 UUID 反查用户账号（日志分析、调试用）
  global_secondary_index {
    name            = "trace_id-index"
    hash_key        = "trace_id"
    projection_type = "ALL"
  }

  tags = merge(var.tags, {
    Name = "unice-trace-mapping"
  })
}

# =============================================================================
# 3. VPC Gateway Endpoints
# =============================================================================
# Gateway 类型端点免费，流量走 AWS 内部网络不经过 NAT Gateway

# DynamoDB Gateway Endpoint
resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc.ids

  tags = merge(var.tags, {
    Name = "${var.name}-dynamodb-endpoint"
  })
}

# S3 Gateway Endpoint（EC2 通过 VPC Endpoint 上传/读取 S3 资源）
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = data.aws_route_tables.vpc.ids

  tags = merge(var.tags, {
    Name = "${var.name}-s3-endpoint"
  })
}
```

### Step 3.2: 创建 `terraform/modules/database/variables.tf`

- [ ] 创建文件 `terraform/modules/database/variables.tf`

```hcl
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "region" {
  description = "AWS 区域（用于 VPC Endpoint service_name）"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet ID 列表（Aurora 子网组需要至少 2 个 AZ）"
  type        = list(string)
}

variable "db_security_group_id" {
  description = "数据库安全组 ID"
  type        = string
}

variable "db_password" {
  description = "Aurora PostgreSQL master 密码"
  type        = string
  sensitive   = true
}

variable "enable_aurora" {
  description = "是否创建 Aurora Serverless v2 集群"
  type        = bool
  default     = true
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
```

### Step 3.3: 创建 `terraform/modules/database/outputs.tf`

- [ ] 创建文件 `terraform/modules/database/outputs.tf`

```hcl
# Aurora 输出（Aurora 禁用时返回空字符串）
output "aurora_endpoint" {
  description = "Aurora 集群写入端点"
  value       = var.enable_aurora ? aws_rds_cluster.aurora[0].endpoint : ""
}

output "aurora_reader_endpoint" {
  description = "Aurora 集群只读端点"
  value       = var.enable_aurora ? aws_rds_cluster.aurora[0].reader_endpoint : ""
}

output "aurora_database_name" {
  description = "Aurora 数据库名称"
  value       = var.enable_aurora ? aws_rds_cluster.aurora[0].database_name : ""
}

# DynamoDB 输出
output "dynamodb_table_name" {
  description = "DynamoDB UUID 映射表名称"
  value       = aws_dynamodb_table.trace_mapping.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB UUID 映射表 ARN"
  value       = aws_dynamodb_table.trace_mapping.arn
}
```

---

## Task 4: Cognito 模块

创建 Cognito User Pool (`unice-user-pool`) 和 App Client (`unice-web-client`)。App Client 无 client secret，使用 `USER_PASSWORD_AUTH` flow，由 Express 后端代为调用 Cognito API 认证。

### Step 4.1: 创建 `terraform/modules/cognito/main.tf`

- [ ] 创建文件 `terraform/modules/cognito/main.tf`

```hcl
# =============================================================================
# Cognito 模块 - 用户认证
# =============================================================================
# - User Pool: unice-user-pool
# - App Client: unice-web-client (无 secret, USER_PASSWORD_AUTH)
# - Express 后端代为调用 Cognito API，无 Hosted UI 依赖
# - JWT 验证由 Express 使用 aws-jwt-verify 库完成
# =============================================================================

resource "aws_cognito_user_pool" "main" {
  name = "unice-user-pool"

  # 密码策略
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = false
    require_uppercase = true
  }

  # 允许用户自行注册
  admin_create_user_config {
    allow_admin_create_user_only = false
  }

  # 邮箱自动验证
  auto_verified_attributes = ["email"]

  # 用户名设置 - 允许邮箱作为用户名登录
  username_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = merge(var.tags, {
    Name = "unice-user-pool"
  })
}

resource "aws_cognito_user_pool_client" "main" {
  name         = "unice-web-client"
  user_pool_id = aws_cognito_user_pool.main.id

  # 无 client secret（适用于服务端直接调用 Cognito API）
  generate_secret = false

  # 认证流程：USER_PASSWORD_AUTH（Express 后端代为调用）
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  supported_identity_providers = ["COGNITO"]

  # Token 有效期
  access_token_validity  = 1    # 1 小时
  id_token_validity      = 1    # 1 小时
  refresh_token_validity = 30   # 30 天

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
```

### Step 4.2: 创建 `terraform/modules/cognito/variables.tf`

- [ ] 创建文件 `terraform/modules/cognito/variables.tf`

```hcl
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
```

### Step 4.3: 创建 `terraform/modules/cognito/outputs.tf`

- [ ] 创建文件 `terraform/modules/cognito/outputs.tf`

```hcl
output "user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "Cognito User Pool ARN"
  value       = aws_cognito_user_pool.main.arn
}

output "user_pool_client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.main.id
}
```

---

## Task 5: EC2 模块

创建 EC2 实例（Ubuntu 24.04）、IAM Role/Instance Profile（DynamoDB/S3/Cognito 权限）、user_data.sh 启动脚本（安装 Node.js 20、pm2、部署 Express 占位应用）。

### Step 5.1: 创建 `terraform/modules/ec2/main.tf`

- [ ] 创建文件 `terraform/modules/ec2/main.tf`

```hcl
# =============================================================================
# EC2 模块 - Express 应用服务器
# =============================================================================
# - Ubuntu 24.04 LTS
# - Node.js 20 + pm2 + Express (via user_data.sh)
# - IAM Role: DynamoDB / S3 / Cognito 访问权限
# - 部署在 Private Subnet，通过 NAT Gateway 访问外网
# =============================================================================

# Ubuntu 24.04 LTS AMI (x86_64)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# -----------------------------------------------------------------------------
# IAM Role & Instance Profile
# -----------------------------------------------------------------------------
resource "aws_iam_role" "app" {
  name = "${var.name}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Name = "${var.name}-ec2-role"
  })
}

resource "aws_iam_instance_profile" "app" {
  name = "${var.name}-ec2-profile"
  role = aws_iam_role.app.name
}

# DynamoDB 访问策略（读写 trace-mapping 表 + GSI 查询）
resource "aws_iam_role_policy" "dynamodb" {
  name = "${var.name}-dynamodb"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = [
          var.dynamodb_table_arn,
          "${var.dynamodb_table_arn}/index/*"
        ]
      }
    ]
  })
}

# S3 访问策略（读写静态资源桶）
resource "aws_iam_role_policy" "s3" {
  name = "${var.name}-s3"
  role = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      }
    ]
  })
}

# Cognito 访问策略（用户注册/登录 API 调用）
resource "aws_iam_role_policy" "cognito" {
  count = var.cognito_user_pool_arn != "" ? 1 : 0
  name  = "${var.name}-cognito"
  role  = aws_iam_role.app.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "cognito-idp:InitiateAuth",
          "cognito-idp:SignUp",
          "cognito-idp:ConfirmSignUp",
          "cognito-idp:GetUser"
        ]
        Resource = [var.cognito_user_pool_arn]
      }
    ]
  })
}

# SSM Session Manager 访问（可选：通过 SSM 连接 Private Subnet 实例）
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.app.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# -----------------------------------------------------------------------------
# EC2 实例
# -----------------------------------------------------------------------------
resource "aws_instance" "app" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = var.subnet_id
  vpc_security_group_ids = var.security_group_ids
  key_name               = var.key_name != "" ? var.key_name : null
  iam_instance_profile   = aws_iam_instance_profile.app.name

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true

    tags = merge(var.tags, {
      Name = "${var.name}-root"
    })
  }

  user_data_base64 = base64encode(templatefile("${path.module}/user_data.sh", {
    region               = var.region
    db_host              = var.db_host
    db_name              = var.db_name
    db_user              = var.db_user
    db_password          = var.db_password
    cognito_user_pool_id = var.cognito_user_pool_id
    cognito_client_id    = var.cognito_client_id
    dynamodb_table_name  = var.dynamodb_table_name
    s3_bucket_name       = var.s3_bucket_name
  }))

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "enabled"
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
```

### Step 5.2: 创建 `terraform/modules/ec2/variables.tf`

- [ ] 创建文件 `terraform/modules/ec2/variables.tf`

```hcl
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "instance_type" {
  description = "EC2 实例类型"
  type        = string
  default     = "t3.medium"
}

variable "subnet_id" {
  description = "EC2 部署的 Private Subnet ID"
  type        = string
}

variable "security_group_ids" {
  description = "EC2 安全组 ID 列表"
  type        = list(string)
}

variable "key_name" {
  description = "SSH 密钥对名称"
  type        = string
  default     = ""
}

variable "root_volume_size" {
  description = "根卷大小 (GB)"
  type        = number
  default     = 20
}

variable "region" {
  description = "AWS 区域"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}

# =============================================================================
# 应用配置（传入 user_data.sh 模板）
# =============================================================================
variable "db_host" {
  description = "Aurora 写入端点（Aurora 禁用时为空字符串）"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "数据库名称"
  type        = string
  default     = "unice"
}

variable "db_user" {
  description = "数据库用户名"
  type        = string
  default     = "unice_admin"
}

variable "db_password" {
  description = "数据库密码"
  type        = string
  sensitive   = true
  default     = ""
}

variable "cognito_user_pool_id" {
  description = "Cognito User Pool ID（Cognito 禁用时为空字符串）"
  type        = string
  default     = ""
}

variable "cognito_client_id" {
  description = "Cognito App Client ID（Cognito 禁用时为空字符串）"
  type        = string
  default     = ""
}

variable "cognito_user_pool_arn" {
  description = "Cognito User Pool ARN（用于 IAM 策略，为空则不创建 Cognito IAM 策略）"
  type        = string
  default     = ""
}

variable "dynamodb_table_name" {
  description = "DynamoDB UUID 映射表名称"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "DynamoDB UUID 映射表 ARN（用于 IAM 策略）"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 静态资源桶名称"
  type        = string
}

variable "s3_bucket_arn" {
  description = "S3 静态资源桶 ARN（用于 IAM 策略）"
  type        = string
}
```

### Step 5.3: 创建 `terraform/modules/ec2/outputs.tf`

- [ ] 创建文件 `terraform/modules/ec2/outputs.tf`

```hcl
output "instance_id" {
  description = "EC2 实例 ID"
  value       = aws_instance.app.id
}

output "instance_private_ip" {
  description = "EC2 实例内网 IP"
  value       = aws_instance.app.private_ip
}

output "instance_availability_zone" {
  description = "EC2 实例可用区"
  value       = aws_instance.app.availability_zone
}

output "iam_role_arn" {
  description = "EC2 IAM Role ARN"
  value       = aws_iam_role.app.arn
}
```

### Step 5.4: 创建 `terraform/modules/ec2/user_data.sh`

- [ ] 创建文件 `terraform/modules/ec2/user_data.sh`（Terraform templatefile 模板）

```bash
#!/bin/bash
set -ex

# 设置环境变量（cloud-init on Ubuntu 24.04 需要）
export HOME=/root
export DEBIAN_FRONTEND=noninteractive

# 日志输出到文件和 console
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "=== Starting Unice Demo Platform setup ==="
echo "Timestamp: $(date)"

# =============================================================================
# 1. 更新系统包
# =============================================================================
echo "=== Updating system packages ==="
apt-get update
apt-get upgrade -y

# 安装基础工具
apt-get install -y curl wget git jq

# =============================================================================
# 2. 安装 Node.js 20 (via NodeSource)
# =============================================================================
echo "=== Installing Node.js 20 ==="
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# =============================================================================
# 3. 安装 pm2（进程管理器）
# =============================================================================
echo "=== Installing pm2 ==="
npm install -g pm2

# =============================================================================
# 4. 创建应用目录和环境配置
# =============================================================================
echo "=== Setting up application ==="
APP_DIR="/opt/unice-app"
mkdir -p $APP_DIR

# 写入环境配置文件（Terraform 模板变量在此处已被替换为实际值）
cat > $APP_DIR/.env <<'ENVEOF'
NODE_ENV=production
PORT=3000
AWS_REGION=${region}
DB_HOST=${db_host}
DB_NAME=${db_name}
DB_USER=${db_user}
DB_PASSWORD=${db_password}
COGNITO_USER_POOL_ID=${cognito_user_pool_id}
COGNITO_CLIENT_ID=${cognito_client_id}
DYNAMODB_TABLE_NAME=${dynamodb_table_name}
S3_BUCKET_NAME=${s3_bucket_name}
ENVEOF

# =============================================================================
# 5. 创建占位 Express 应用
# =============================================================================
# 完整应用代码（app/ 目录）将在后续部署步骤中同步
# 此处创建最小可用应用，确保 ALB 健康检查通过

cat > $APP_DIR/package.json <<'PKGEOF'
{
  "name": "unice-demo",
  "version": "1.0.0",
  "description": "CloudFront Demo Platform - Unice",
  "main": "server.js",
  "scripts": {
    "start": "node server.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "dotenv": "^16.4.0"
  }
}
PKGEOF

cat > $APP_DIR/server.js <<'APPEOF'
require('dotenv').config();
const express = require('express');
const app = express();
const PORT = process.env.PORT || 3000;

// 健康检查端点（ALB Target Group 使用）
app.get('/api/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    traceId: req.headers['x-trace-id'] || 'none',
    version: '1.0.0',
    env: {
      region: process.env.AWS_REGION || 'unknown',
      dbConfigured: !!process.env.DB_HOST,
      cognitoConfigured: !!process.env.COGNITO_USER_POOL_ID
    }
  });
});

// 调试端点 - 返回所有 request headers
app.get('/api/debug', (req, res) => {
  res.json({
    headers: req.headers,
    ip: req.ip,
    method: req.method,
    url: req.url,
    protocol: req.protocol,
    hostname: req.hostname,
    timestamp: new Date().toISOString()
  });
});

// 延迟端点 - 模拟慢响应（测试 CloudFront Origin Timeout）
app.get('/api/delay/:ms', (req, res) => {
  const ms = parseInt(req.params.ms) || 1000;
  const capped = Math.min(ms, 30000); // 最大 30 秒
  setTimeout(() => {
    res.json({
      delayed: capped,
      timestamp: new Date().toISOString()
    });
  }, capped);
});

// 默认路由
app.get('/', (req, res) => {
  res.send([
    '<h1>Unice Demo - CloudFront Demo Platform</h1>',
    '<p>Platform is running. Full app deployment pending.</p>',
    '<ul>',
    '<li><a href="/api/health">/api/health</a> - Health check</li>',
    '<li><a href="/api/debug">/api/debug</a> - Debug headers</li>',
    '<li><a href="/api/delay/1000">/api/delay/1000</a> - 1s delay test</li>',
    '</ul>'
  ].join('\n'));
});

app.listen(PORT, '0.0.0.0', () => {
  console.log('Unice Demo server running on port ' + PORT);
});
APPEOF

# =============================================================================
# 6. 安装依赖并启动应用
# =============================================================================
cd $APP_DIR
npm install --production

# 使用 pm2 启动应用
pm2 start server.js --name unice-app
pm2 save

# 配置 pm2 开机自启
pm2 startup systemd -u root --hp /root

# =============================================================================
# 7. 健康检查
# =============================================================================
echo "=== Final health check ==="
sleep 3

if curl -s http://127.0.0.1:3000/api/health | grep -q '"status":"ok"'; then
    echo "Health check: PASSED"
else
    echo "Health check: FAILED"
    pm2 logs unice-app --lines 20 || true
fi

echo "=== Unice Demo Platform setup completed ==="
echo "Timestamp: $(date)"
```

---

## Task 6: ALB 模块 (Internal)

创建 Internal Application Load Balancer、Target Group（port 3000, health check `/api/health`）、HTTP Listener（port 80）。ALB 部署在 Private Subnet，仅接受来自 VPC Origin 安全组的流量。

### Step 6.1: 创建 `terraform/modules/alb/main.tf`

- [ ] 创建文件 `terraform/modules/alb/main.tf`

```hcl
# =============================================================================
# ALB 模块 - Internal Application Load Balancer
# =============================================================================
# - internal = true: ALB 无公网 IP，完全内网化
# - 部署在 Private Subnet
# - 仅接受来自 VPC Origin 安全组的 HTTP 80 流量
# - 转发到 EC2 Express (port 3000)
# - CloudFront 通过 VPC Origin ENI 连接此 ALB
# =============================================================================

resource "aws_lb" "main" {
  name               = "${var.name}-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = var.security_group_ids
  subnets            = var.private_subnet_ids

  enable_deletion_protection = false

  tags = merge(var.tags, {
    Name = "${var.name}-alb"
  })
}

# Target Group - EC2 Express (port 3000)
resource "aws_lb_target_group" "main" {
  name     = "${var.name}-tg"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    interval            = 30
    matcher             = "200"
    path                = "/api/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  tags = merge(var.tags, {
    Name = "${var.name}-tg"
  })
}

# 注册 EC2 实例到 Target Group
resource "aws_lb_target_group_attachment" "main" {
  target_group_arn = aws_lb_target_group.main.arn
  target_id        = var.target_instance_id
  port             = 3000
}

# HTTP Listener (port 80) - CloudFront VPC Origin 以 HTTP 连接 ALB
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.main.arn
  }

  tags = merge(var.tags, {
    Name = "${var.name}-http-listener"
  })
}
```

### Step 6.2: 创建 `terraform/modules/alb/variables.tf`

- [ ] 创建文件 `terraform/modules/alb/variables.tf`

```hcl
variable "name" {
  description = "资源名称前缀"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private Subnet ID 列表（ALB 需要至少 2 个不同 AZ 的子网）"
  type        = list(string)
}

variable "security_group_ids" {
  description = "ALB 安全组 ID 列表"
  type        = list(string)
}

variable "target_instance_id" {
  description = "EC2 实例 ID（注册到 Target Group）"
  type        = string
}

variable "tags" {
  description = "资源标签"
  type        = map(string)
  default     = {}
}
```

### Step 6.3: 创建 `terraform/modules/alb/outputs.tf`

- [ ] 创建文件 `terraform/modules/alb/outputs.tf`

```hcl
output "alb_arn" {
  description = "ALB ARN"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "ALB DNS 名称（Part 2 CloudFront VPC Origin 使用）"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "ALB Hosted Zone ID"
  value       = aws_lb.main.zone_id
}

output "target_group_arn" {
  description = "Target Group ARN"
  value       = aws_lb_target_group.main.arn
}
```
