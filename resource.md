# CloudFront 演示平台 — AWS 资源清单

> 其他开发者只需替换本文档中的资源值和 `terraform.tfvars` 即可在自己的账号部署。

---

## 1. 基础信息

| 属性 | 值 |
|------|-----|
| AWS Account | `434465421667` |
| Region | `ap-northeast-1` (Tokyo) |
| Profile | `default` |
| 站点域名 | `unice.keithyu.cloud` |
| 站点 URL | `https://unice.keithyu.cloud` |

---

## 2. VPC 网络

| 属性 | 值 |
|------|-----|
| VPC ID | `vpc-086e15047c7f68e87` |
| VPC Name | `keithyu-tokyo-vpc` |
| CIDR | `10.0.0.0/16` |
| NAT Gateway | `nat-07585e85b4e94b406` (EIP: `54.199.205.84`) |

### Private Subnets

| Subnet ID | CIDR | AZ |
|-----------|------|----|
| `subnet-04b63b752e16ea94d` | `10.0.11.0/24` | `ap-northeast-1a` |
| `subnet-0e071f31a7d6d1c17` | `10.0.12.0/24` | `ap-northeast-1c` |
| `subnet-0526989496f5c5edc` | `10.0.13.0/24` | `ap-northeast-1d` |

---

## 3. CloudFront

| 属性 | 值 |
|------|-----|
| Distribution ID | `EKM1WK5FUL5ZU` |
| Domain | `dozy2d80tdxp3.cloudfront.net` |
| CNAME | `unice.keithyu.cloud` |
| Price Class | `PriceClass_200` |
| Staging Distribution ID | `E33LBQS92G8CAR` |
| Staging Domain | `d1sg184z4sw75f.cloudfront.net` |

### Origins

| Origin ID | Domain |
|-----------|--------|
| `s3-origin` | `unice-demo-static-434465421667-apne1.s3.ap-northeast-1.amazonaws.com` |
| `alb-vpc-origin` | `internal-unice-demo-alb-2118190999.ap-northeast-1.elb.amazonaws.com` |

### CloudFront Functions

| Function Name | 用途 |
|---------------|------|
| `unice-demo-cf-url-rewrite` | Viewer Request: URL 重写 (挂载在 Default Behavior) |
| `unice-demo-cf-ab-test` | A/B 测试路由 |
| `unice-demo-cf-geo-redirect` | 地理位置重定向 |

---

## 4. WAF

| 属性 | 值 |
|------|-----|
| Web ACL Name | `unice-demo-waf` |
| Web ACL ID | `dbb47c0f-062b-434a-a1be-01873e27e59b` |
| Web ACL ARN | `arn:aws:wafv2:us-east-1:434465421667:global/webacl/unice-demo-waf/dbb47c0f-062b-434a-a1be-01873e27e59b` |
| Scope | `CLOUDFRONT` (us-east-1) |

### 规则列表

| Priority | 规则名称 | 类型 |
|----------|----------|------|
| 1 | `AWS-AWSManagedRulesCommonRuleSet` | AWS 托管规则 |
| 2 | `AWS-AWSManagedRulesKnownBadInputsRuleSet` | AWS 托管规则 |
| 3 | `AWS-AWSManagedRulesBotControlRuleSet` | AWS 托管规则 |
| 4 | `RateLimitRule` | 自定义速率限制 |
| 5 | `AWS-AWSManagedRulesAmazonIpReputationList` | AWS 托管规则 |
| 6 | `GeoBlockRule` | 自定义地理封禁 |

---

## 5. S3

| 属性 | 值 |
|------|-----|
| Bucket Name | `unice-demo-static-434465421667-apne1` |
| 用途 | 静态资源 (HTML/CSS/JS/Images) |
| Region | `ap-northeast-1` |

---

## 6. EC2

| 属性 | 值 |
|------|-----|
| Instance ID | `i-0b3909ccf20886d49` |
| Instance Type | `t3.medium` |
| AMI | `ami-09d192ce734c5864c` |
| Private IP | `10.0.11.138` |
| Subnet | `subnet-04b63b752e16ea94d` (ap-northeast-1a) |
| Security Group | `sg-05b4d37af40851c20` (`unice-demo-ec2-sg`) |
| State | `running` |
| 用途 | Node.js Express 应用服务器 |

---

## 7. ALB

| 属性 | 值 |
|------|-----|
| Name | `unice-demo-alb` |
| DNS | `internal-unice-demo-alb-2118190999.ap-northeast-1.elb.amazonaws.com` |
| ARN | `arn:aws:elasticloadbalancing:ap-northeast-1:434465421667:loadbalancer/app/unice-demo-alb/b4e2a78bf1eeeddd` |
| Scheme | `internal` |
| Type | `application` |
| Security Group | `sg-008f9350b6aa9f27f` (`unice-demo-alb-sg`) |
| Target Group | `unice-demo-tg` (HTTP:3000) |

---

## 8. Aurora Serverless v2

| 属性 | 值 |
|------|-----|
| Cluster Name | `unice-demo-aurora` |
| Engine | `aurora-postgresql` 16.4 |
| Writer Endpoint | `unice-demo-aurora.cluster-czyuimqioyle.ap-northeast-1.rds.amazonaws.com` |
| Reader Endpoint | `unice-demo-aurora.cluster-ro-czyuimqioyle.ap-northeast-1.rds.amazonaws.com` |
| Port | `5432` |
| Database Name | `unice` |
| Username | `unice_admin` |

**连接字符串示例：**
```
postgresql://unice_admin:<password>@unice-demo-aurora.cluster-czyuimqioyle.ap-northeast-1.rds.amazonaws.com:5432/unice
```

---

## 9. Cognito

| 属性 | 值 |
|------|-----|
| User Pool Name | `unice-user-pool` |
| User Pool ID | `ap-northeast-1_XK2IURmZg` |
| App Client Name | `unice-web-client` |
| App Client ID | `hsecq8tovfjmd8cfp4rvdhrqm` |

---

## 10. DynamoDB

| Table Name | Partition Key | Sort Key | Billing | 用途 |
|------------|--------------|----------|---------|------|
| `unice-demo-cache-tags` | `tag` (HASH) | `url` (RANGE) | PAY_PER_REQUEST | Cache Tag 与 URL 映射，用于 Tag-Based Invalidation |
| `unice-trace-mapping` | `cognito_user_id` (HASH) | - | PAY_PER_REQUEST | Cognito 用户与 X-Ray Trace 映射 |

---

## 11. Lambda

### Lambda@Edge (us-east-1)

| Function Name | ARN | Runtime | 用途 |
|---------------|-----|---------|------|
| `unice-demo-cache-tag-origin-response` | `arn:aws:lambda:us-east-1:434465421667:function:unice-demo-cache-tag-origin-response:1` | `nodejs20.x` | Origin Response: 解析 Cache-Tag header 并写入 DynamoDB |

### Lambda (ap-northeast-1)

| Function Name | ARN | Runtime | 用途 |
|---------------|-----|---------|------|
| `unice-demo-cache-tag-invalidation` | `arn:aws:lambda:ap-northeast-1:434465421667:function:unice-demo-cache-tag-invalidation` | `nodejs20.x` | 根据 tag 查询 DynamoDB，批量调用 CloudFront CreateInvalidation |

---

## 12. ACM 证书

| Domain | ARN | Region | 用途 |
|--------|-----|--------|------|
| `*.keithyu.cloud` | `arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2` | `us-east-1` | CloudFront Viewer Certificate |
| `*.keithyu.cloud` | `arn:aws:acm:ap-northeast-1:434465421667:certificate/fc0dde72-5e49-4238-a37a-f5ac77ceb8d6` | `ap-northeast-1` | ALB HTTPS (如需) |

---

## 13. Route53

| 属性 | 值 |
|------|-----|
| Zone Name | `keithyu.cloud` |
| Zone ID | `Z08736783U3DQRJUZ1EXF` |
| CNAME Record | `unice.keithyu.cloud` -> `dozy2d80tdxp3.cloudfront.net` |

---

## 14. 安全组

| SG ID | Name | 用途 |
|-------|------|------|
| `sg-0d97718bd9a94aa03` | `unice-demo-vpc-origin-sg` | CloudFront VPC Origin ENIs |
| `sg-008f9350b6aa9f27f` | `unice-demo-alb-sg` | Internal ALB - 仅允许 VPC Origin 访问 |
| `sg-05b4d37af40851c20` | `unice-demo-ec2-sg` | EC2 Express 实例 |
| `sg-0a212fc941d67f617` | `unice-demo-db-sg` | Aurora Serverless v2 PostgreSQL |

---

## 快速参考 - 环境变量模板

```bash
# 基础信息
export AWS_REGION="ap-northeast-1"
export AWS_PROFILE="default"
export SITE_DOMAIN="unice.keithyu.cloud"

# CloudFront
export CF_DISTRIBUTION_ID="EKM1WK5FUL5ZU"
export CF_DOMAIN="dozy2d80tdxp3.cloudfront.net"
export CF_STAGING_ID="E33LBQS92G8CAR"
export CF_STAGING_DOMAIN="d1sg184z4sw75f.cloudfront.net"

# S3
export S3_BUCKET="unice-demo-static-434465421667-apne1"

# EC2
export EC2_INSTANCE_ID="i-0b3909ccf20886d49"

# ALB
export ALB_DNS="internal-unice-demo-alb-2118190999.ap-northeast-1.elb.amazonaws.com"

# Aurora PostgreSQL
export DB_HOST="unice-demo-aurora.cluster-czyuimqioyle.ap-northeast-1.rds.amazonaws.com"
export DB_HOST_RO="unice-demo-aurora.cluster-ro-czyuimqioyle.ap-northeast-1.rds.amazonaws.com"
export DB_PORT="5432"
export DB_NAME="unice"
export DB_USER="unice_admin"

# Cognito
export COGNITO_USER_POOL_ID="ap-northeast-1_XK2IURmZg"
export COGNITO_CLIENT_ID="hsecq8tovfjmd8cfp4rvdhrqm"

# DynamoDB
export DYNAMODB_CACHE_TAGS_TABLE="unice-demo-cache-tags"
export DYNAMODB_TRACE_TABLE="unice-trace-mapping"

# Lambda
export TAG_LAMBDA_EDGE_ARN="arn:aws:lambda:us-east-1:434465421667:function:unice-demo-cache-tag-origin-response:1"
export TAG_INVALIDATION_LAMBDA_ARN="arn:aws:lambda:ap-northeast-1:434465421667:function:unice-demo-cache-tag-invalidation"

# WAF
export WAF_WEB_ACL_ARN="arn:aws:wafv2:us-east-1:434465421667:global/webacl/unice-demo-waf/dbb47c0f-062b-434a-a1be-01873e27e59b"

# VPC
export VPC_ID="vpc-086e15047c7f68e87"
export PRIVATE_SUBNETS="subnet-04b63b752e16ea94d,subnet-0e071f31a7d6d1c17,subnet-0526989496f5c5edc"

# Route53
export ROUTE53_ZONE_ID="Z08736783U3DQRJUZ1EXF"

# ACM
export ACM_CERT_ARN_GLOBAL="arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2"
export ACM_CERT_ARN_REGIONAL="arn:aws:acm:ap-northeast-1:434465421667:certificate/fc0dde72-5e49-4238-a37a-f5ac77ceb8d6"
```

---

## 如何在其他账号部署

1. Fork 项目
2. 创建 VPC（需要 Private Subnet + NAT Gateway）
3. 创建 ACM 证书（us-east-1 用于 CloudFront，ap-northeast-1 用于 ALB）和 Route53 Hosted Zone
4. 复制 `terraform.tfvars.example` -> `terraform.tfvars`
5. 替换本文档中的值到 `terraform.tfvars`
6. `terraform init && terraform apply`
