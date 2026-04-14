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

# 入站：允许来自 CloudFront 自动管理的 VPC Origins Service SG
# CloudFront VPC Origin 创建的 ENI 使用 AWS 托管的安全组，非用户创建的 vpc_origin SG
# 需要通过 data source 引用该安全组（按名称查找）
data "aws_security_group" "cloudfront_vpc_origins_service" {
  filter {
    name   = "group-name"
    values = ["CloudFront-VPCOrigins-Service-SG"]
  }
  filter {
    name   = "vpc-id"
    values = [var.vpc_id]
  }
}

resource "aws_security_group_rule" "alb_ingress_cloudfront_managed" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = data.aws_security_group.cloudfront_vpc_origins_service.id
  security_group_id        = aws_security_group.alb.id
  description              = "Allow HTTP from CloudFront managed VPC Origins Service SG"
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
