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
