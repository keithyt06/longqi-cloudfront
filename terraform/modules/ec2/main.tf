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
  count = var.enable_cognito ? 1 : 0
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
          "cognito-idp:AdminConfirmSignUp",
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
