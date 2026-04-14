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
