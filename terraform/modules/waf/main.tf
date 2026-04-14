# =============================================================================
# WAF Web ACL for CloudFront (us-east-1)
# 6 条规则: Common Rule Set, Known Bad Inputs, Bot Control (条件),
#           Rate Limit, IP Reputation, Geo Block
# =============================================================================

resource "aws_wafv2_web_acl" "main" {
  name        = "${var.name}-waf"
  description = "WAF Web ACL for ${var.name} CloudFront distribution"
  scope       = "CLOUDFRONT"

  # 默认动作: 允许 — 只有匹配规则的请求才被处理
  default_action {
    allow {}
  }

  # ===========================================================================
  # Rule 1: AWS Common Rule Set (优先级 1, Count 模式)
  # 覆盖 OWASP Top 10 常见攻击: SQL 注入、XSS、SSRF 等
  # 建议: 初始设为 Count 观察误报，确认无误后切换为 Block (override_action { none {} })
  # ===========================================================================
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-common-rules"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 2: AWS Known Bad Inputs (优先级 2, Block)
  # 检测已知恶意输入模式: Log4j 漏洞利用 payload、恶意 User-Agent 等
  # ===========================================================================
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-known-bad-inputs"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 3: AWS Bot Control — TARGETED 级别 (优先级 3, 条件启用)
  # 基于行为分析 + ML 模型检测高级爬虫和自动化工具
  # 配合 WAF JS SDK (aws-waf-token cookie) 区分真实浏览器和无头脚本
  # 费用: $10/月基础费 + $1/百万请求，通过 enable_bot_control 控制
  #
  # managed_rule_group_configs 设置 inspection_level = TARGETED:
  #   - Common 级别: HTTP 指纹识别已知机器人
  #   - Targeted 级别: 在 Common 基础上增加行为分析、ML 模型、JS 验证
  # ===========================================================================
  dynamic "rule" {
    for_each = var.enable_bot_control ? [1] : []
    content {
      name     = "AWS-AWSManagedRulesBotControlRuleSet"
      priority = 3

      override_action {
        count {}
      }

      statement {
        managed_rule_group_statement {
          name        = "AWSManagedRulesBotControlRuleSet"
          vendor_name = "AWS"

          # TARGETED inspection level — 启用行为分析和 ML 检测
          managed_rule_group_configs {
            aws_managed_rules_bot_control_rule_set {
              inspection_level = "TARGETED"
            }
          }

          # HTTP 库 (curl/Python requests) 和非浏览器 UA 设为 Count（允许 API 客户端）
          rule_action_override {
            name = "CategoryHttpLibrary"
            action_to_use {
              count {}
            }
          }
          rule_action_override {
            name = "SignalNonBrowserUserAgent"
            action_to_use {
              count {}
            }
          }
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-bot-control"
        sampled_requests_enabled   = true
      }
    }
  }

  # ===========================================================================
  # Rule 4: Rate Limit — 2000 次/5 分钟 (优先级 4, Block)
  # 同一 IP 在 5 分钟评估窗口内超过 2000 次请求将被封禁
  # 防止暴力破解、简单 DDoS、API 滥用
  # ===========================================================================
  rule {
    name     = "RateLimitRule"
    priority = 4

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-limit"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 5: AWS IP Reputation List (优先级 5, Count)
  # AWS 维护的恶意 IP 信誉库: 僵尸网络节点、匿名代理、Tor 出口节点等
  # Count 模式用于监控，避免误封正常用户
  # ===========================================================================
  rule {
    name     = "AWS-AWSManagedRulesAmazonIpReputationList"
    priority = 5

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-ip-reputation"
      sampled_requests_enabled   = true
    }
  }

  # ===========================================================================
  # Rule 6: Geo Block — 自定义国家封禁 (优先级 6, Block)
  # 封禁来自指定国家的所有请求，配合 CloudFront geo_restriction 使用
  # 国家代码列表通过 var.geo_block_countries 传入
  # 仅在提供了国家代码列表时才创建此规则
  # ===========================================================================
  dynamic "rule" {
    for_each = length(var.geo_block_countries) > 0 ? [1] : []
    content {
      name     = "GeoBlockRule"
      priority = 6

      action {
        block {}
      }

      statement {
        geo_match_statement {
          country_codes = var.geo_block_countries
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-geo-block"
        sampled_requests_enabled   = true
      }
    }
  }

  # ===========================================================================
  # Web ACL 全局可观测性配置
  # ===========================================================================
  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-waf"
    sampled_requests_enabled   = true
  }

  tags = merge(var.tags, {
    Name = "${var.name}-waf"
  })
}
