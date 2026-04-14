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
  access_token_validity  = 1  # 1 小时
  id_token_validity      = 1  # 1 小时
  refresh_token_validity = 30 # 30 天

  token_validity_units {
    access_token  = "hours"
    id_token      = "hours"
    refresh_token = "days"
  }
}
