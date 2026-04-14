# CloudFront 全功能演示平台 - 实施计划索引

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个参考 unice.com 的功能性电商模拟网站，作为 CloudFront 全栈功能（多源路由、缓存策略、Functions、WAF Bot Control、VPC Origin、Continuous Deployment、签名 URL 等）的演示和测试平台。

**Architecture:** S3（静态）+ EC2 Express（动态 API）双源，CloudFront 统一入口，Internal ALB 通过 VPC Origin 连接，全内网架构。Cognito 做用户认证，DynamoDB 做 UUID 追踪映射，Aurora Serverless v2 存商品/订单数据。

**Tech Stack:** Terraform, AWS CloudFront, ALB, EC2, S3, WAF, Cognito, Aurora Serverless v2, DynamoDB, Node.js Express, EJS

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

**Design Spec:** `docs/superpowers/specs/2026-04-14-cloudfront-demo-platform-design.md`

---

## 计划文件结构

由于计划规模较大（总计 13,592 行），拆分为 8 个文件，按阶段组织：

### Phase 1: Terraform 基础设施 (Tasks 1-6)
- **文件**: [part1.md](2026-04-14-cloudfront-demo-platform-part1.md) (1,955 行)
- **内容**: 项目脚手架 + Network 模块（安全组）+ S3 模块 + Database 模块（Aurora + DynamoDB）+ Cognito 模块 + EC2 模块 + ALB 模块

### Phase 2A: Express 应用核心 (Tasks 7-9)
- **文件**: [part2a.md](2026-04-14-cloudfront-demo-platform-part2a.md) (1,657 行)
- **内容**: Express 脚手架 + 中间件（UUID tracker + Cognito auth）+ 核心路由（products/user/cart/orders）+ 调试路由 + seed 脚本

### Phase 2B: Express 视图与静态资源 (Task 10)
- **文件**: [part2b.md](2026-04-14-cloudfront-demo-platform-part2b.md) (2,828 行)
- **内容**: EJS 模板（layout/index/products/cart/login/debug）+ CSS + JS + 错误页面 HTML

### Phase 3: CloudFront + Security (Tasks 11-15)
- **文件**: [part3.md](2026-04-14-cloudfront-demo-platform-part3.md) (2,438 行)
- **内容**: CloudFront Functions (3个) + CloudFront Distribution 模块 + WAF 模块 + Continuous Deployment 模块 + Root 模块集成

### Phase 4A: Hands-on 文档 01-04 (Task 16)
- **文件**: [part4a.md](2026-04-14-cloudfront-demo-platform-part4a.md) (1,242 行)
- **内容**: 多源分发 + 缓存策略 + CloudFront Functions + WAF 基础规则

### Phase 4B-1: Hands-on 文档 05-06 (Task 17a)
- **文件**: [part4b1.md](2026-04-14-cloudfront-demo-platform-part4b1.md) (1,105 行)
- **内容**: WAF Bot Control + JS SDK + 签名 URL/Cookie

### Phase 4B-2: Hands-on 文档 07-08 (Task 17b)
- **文件**: [part4b2.md](2026-04-14-cloudfront-demo-platform-part4b2.md) (930 行)
- **内容**: 地理限制 + 自定义错误页面

### Phase 4C: Hands-on 文档 09-11 (Task 18)
- **文件**: [part4c.md](2026-04-14-cloudfront-demo-platform-part4c.md) (1,437 行)
- **内容**: OAC for S3 + VPC Origin + Continuous Deployment

### Phase 5: Tag-Based Invalidation (Tasks 19-21)
- **文件**: [part5.md](2026-04-14-cloudfront-demo-platform-part5.md) (2,329 行)
- **内容**: Tag-Based Invalidation Terraform 模块（Lambda@Edge + DynamoDB + Step Functions）+ Express 集成 + Hands-on 12

---

## Task 总览

| Task | Phase | 内容 | 文件 |
|------|-------|------|------|
| 1 | 1 | Terraform 脚手架 + Network 模块 | part1 |
| 2 | 1 | S3 模块 | part1 |
| 3 | 1 | Database 模块 (Aurora + DynamoDB) | part1 |
| 4 | 1 | Cognito 模块 | part1 |
| 5 | 1 | EC2 模块 + user_data | part1 |
| 6 | 1 | ALB 模块 (Internal) | part1 |
| 7 | 2A | Express 脚手架 + 中间件 | part2a |
| 8 | 2A | 核心业务路由 | part2a |
| 9 | 2A | 调试路由 + seed 脚本 | part2a |
| 10 | 2B | EJS 视图 + CSS + JS + 错误页面 | part2b |
| 11 | 3 | CloudFront Functions (3个) | part3 |
| 12 | 3 | CloudFront Distribution 模块 | part3 |
| 13 | 3 | WAF 模块 | part3 |
| 14 | 3 | CloudFront Continuous Deployment 模块 | part3 |
| 15 | 3 | Root 模块集成 | part3 |
| 16 | 4A | Hands-on 01-04 | part4a |
| 17a | 4B-1 | Hands-on 05-06 | part4b1 |
| 17b | 4B-2 | Hands-on 07-08 | part4b2 |
| 18 | 4C | Hands-on 09-11 | part4c |
| 19 | 5 | Tag-Based Invalidation Terraform 模块 | part5 |
| 20 | 5 | Express 集成 + Lambda 代码 | part5 |
| 21 | 5 | Hands-on 12: Tag-Based Invalidation | part5 |

---

## 执行顺序

建议按 Phase 顺序执行，Phase 内的 Tasks 可以并行：

1. **Phase 1** (Tasks 1-6) → Terraform 基础设施必须先就位
2. **Phase 2A + 2B** (Tasks 7-10) → Express 应用可以并行开发
3. **Phase 3** (Tasks 11-15) → CloudFront 依赖 Phase 1 的 ALB/S3 输出
4. **Phase 4** (Tasks 16-18) → Hands-on 文档可以最后写，也可以和 Phase 3 并行
5. **Phase 5** (Tasks 19-21) → Tag-Based Invalidation 依赖 Phase 3 的 CloudFront Distribution + Phase 2 的 Express 应用
