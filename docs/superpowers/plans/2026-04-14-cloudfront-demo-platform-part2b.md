# CloudFront 全功能演示平台 - 实施计划 Part 2B

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 创建 Express EJS 视图层、前端静态资源（CSS/JS）和 CloudFront 自定义错误页面，构成电商模拟网站的完整前端展示层。

**Architecture:** EJS 模板通过 layout 继承实现统一导航/footer/WAF JS SDK 注入。前端 JS 使用 fetch API 与后端 API 交互，JWT token 存储在 localStorage。错误页面为纯静态 HTML，上传到 S3 后由 CloudFront Custom Error Response 提供服务。

**Tech Stack:** EJS, CSS3 (Flexbox/Grid), Vanilla JavaScript (fetch API), HTML5

**Base Directory:** `/root/keith-space/2026-project/longqi-cloudfront/`

---

## 文件结构总览 (Part 2B)

```
app/
├── views/
│   ├── layout.ejs               # 公共布局（WAF JS SDK、导航栏、footer）
│   ├── index.ejs                # 首页（推荐商品卡片网格）
│   ├── products.ejs             # 商品列表（网格+分类筛选+分页）
│   ├── product-detail.ejs       # 商品详情（图片+名称+价格+描述+加购）
│   ├── cart.ejs                 # 购物车（商品列表+数量+总价+下单）
│   ├── login.ejs                # 登录/注册（双 tab 切换表单）
│   └── debug.ejs                # 调试页（headers/cookies 表格+trace-id）
├── public/
│   ├── css/
│   │   └── style.css            # 电商样式（深色导航、商品卡片、响应式网格）
│   └── js/
│       └── main.js              # 前端逻辑（购物车 AJAX、登录 fetch、token 管理）
static/
└── errors/
    ├── 403.html                 # 品牌化 403 Forbidden 页面
    ├── 404.html                 # 品牌化 404 Not Found 页面
    ├── 500.html                 # 品牌化 500 Internal Server Error 页面
    └── 502.html                 # 品牌化 502 Bad Gateway 页面
```

---

## Phase 2B: Express 视图与静态资源 (Task 10)

### Task 10: EJS 视图 + CSS + JS + 错误页面

创建完整的 EJS 视图层（7 个模板）、前端静态资源（CSS + JS）和 4 个 CloudFront 自定义错误页面。所有视图通过 layout.ejs 继承统一的导航栏、WAF JS SDK 引入和 footer。前端 JS 使用原生 fetch API，无外部框架依赖。

#### Step 10.1: 创建 `app/views/layout.ejs` — 公共布局

- [ ] 创建文件 `app/views/layout.ejs`，包含 HTML 骨架、WAF JS SDK、导航栏、footer、内容插槽

```ejs
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title><%= typeof title !== 'undefined' ? title + ' - ' : '' %>Unice Demo</title>

  <!-- WAF JS SDK: Bot Control 浏览器指纹采集，生成 aws-waf-token cookie -->
  <script type="text/javascript" src="/challenge.js" defer></script>

  <!-- 全局样式 -->
  <link rel="stylesheet" href="/static/css/style.css">
</head>
<body>

  <!-- ===== 导航栏 ===== -->
  <nav class="navbar">
    <div class="nav-container">
      <!-- 品牌 Logo -->
      <a href="/" class="nav-brand">Unice Demo</a>

      <!-- 导航链接 -->
      <ul class="nav-links">
        <li><a href="/" class="nav-link<%= typeof currentPage !== 'undefined' && currentPage === 'home' ? ' active' : '' %>">Home</a></li>
        <li><a href="/products" class="nav-link<%= typeof currentPage !== 'undefined' && currentPage === 'products' ? ' active' : '' %>">Products</a></li>
        <li>
          <a href="/cart" class="nav-link<%= typeof currentPage !== 'undefined' && currentPage === 'cart' ? ' active' : '' %>">
            Cart
            <!-- 购物车数量徽章（JS 动态更新） -->
            <span id="cart-badge" class="badge" style="display:none;">0</span>
          </a>
        </li>
        <li>
          <a href="/login" class="nav-link<%= typeof currentPage !== 'undefined' && currentPage === 'login' ? ' active' : '' %>" id="nav-login-link">
            Login
          </a>
        </li>
        <li><a href="/debug" class="nav-link<%= typeof currentPage !== 'undefined' && currentPage === 'debug' ? ' active' : '' %>">Debug</a></li>
      </ul>

      <!-- 移动端菜单按钮 -->
      <button class="nav-toggle" id="nav-toggle" aria-label="切换导航菜单">
        <span></span><span></span><span></span>
      </button>
    </div>
  </nav>

  <!-- ===== 主内容区 ===== -->
  <main class="main-content">
    <%- body %>
  </main>

  <!-- ===== Footer ===== -->
  <footer class="footer">
    <div class="footer-container">
      <p>&copy; 2026 Unice Demo — CloudFront 全功能演示平台</p>
      <p class="footer-sub">
        由 AWS SA Keith 构建 |
        <a href="/debug">调试信息</a> |
        <a href="/api/health" target="_blank">健康检查</a>
      </p>
      <!-- Trace ID 显示（JS 动态填充） -->
      <p class="footer-trace" id="footer-trace-id"></p>
    </div>
  </footer>

  <!-- 全局前端 JS -->
  <script src="/static/js/main.js"></script>
</body>
</html>
```

#### Step 10.2: 创建 `app/views/index.ejs` — 首页

- [ ] 创建文件 `app/views/index.ejs`，展示推荐商品卡片网格，继承 layout

```ejs
<% layout('layout') -%>

<!-- ===== Hero Banner ===== -->
<section class="hero">
  <div class="hero-content">
    <h1>CloudFront 全功能演示平台</h1>
    <p>基于 Amazon CloudFront 构建的电商模拟网站，覆盖多源路由、缓存策略、WAF Bot Control、VPC Origin、签名 URL 等核心功能。</p>
    <a href="/products" class="btn btn-primary">浏览商品</a>
  </div>
</section>

<!-- ===== 推荐商品网格 ===== -->
<section class="section">
  <h2 class="section-title">推荐商品</h2>
  <div class="product-grid" id="featured-products">
    <!-- JS 动态加载，或服务端渲染 -->
    <% if (typeof products !== 'undefined' && products.length > 0) { %>
      <% products.forEach(function(product) { %>
        <div class="product-card">
          <a href="/products/<%= product.id %>">
            <div class="product-image">
              <img src="<%= product.image_url || '/static/images/placeholder.png' %>"
                   alt="<%= product.name %>"
                   loading="lazy">
            </div>
            <div class="product-info">
              <h3 class="product-name"><%= product.name %></h3>
              <p class="product-category"><%= product.category %></p>
              <p class="product-price">&yen;<%= product.price %></p>
            </div>
          </a>
        </div>
      <% }); %>
    <% } else { %>
      <!-- 无数据时的占位提示 -->
      <p class="empty-state">暂无推荐商品，请稍后再试。</p>
    <% } %>
  </div>
</section>

<!-- ===== 功能特性概览 ===== -->
<section class="section section-alt">
  <h2 class="section-title">平台演示功能</h2>
  <div class="feature-grid">
    <div class="feature-card">
      <h3>多源路由</h3>
      <p>S3 静态 + ALB 动态双源，10 条 Cache Behavior 按路径分发</p>
    </div>
    <div class="feature-card">
      <h3>WAF Bot Control</h3>
      <p>JS SDK 浏览器指纹检测，区分真实用户与自动化脚本</p>
    </div>
    <div class="feature-card">
      <h3>VPC Origin</h3>
      <p>Internal ALB 零公网暴露，CloudFront 通过 VPC ENI 直连</p>
    </div>
    <div class="feature-card">
      <h3>边缘计算</h3>
      <p>CloudFront Functions 实现 URL 重写、A/B 测试、地理重定向</p>
    </div>
    <div class="feature-card">
      <h3>签名 URL</h3>
      <p>RSA 密钥对签名保护会员内容，1 小时有效期</p>
    </div>
    <div class="feature-card">
      <h3>灰度发布</h3>
      <p>Continuous Deployment 支持 5% 流量灰度验证</p>
    </div>
  </div>
</section>
```

#### Step 10.3: 创建 `app/views/products.ejs` — 商品列表

- [ ] 创建文件 `app/views/products.ejs`，包含商品网格、分类筛选和分页控件

```ejs
<% layout('layout') -%>

<section class="section">
  <h1 class="page-title">商品列表</h1>

  <!-- ===== 分类筛选栏 ===== -->
  <div class="filter-bar">
    <div class="filter-group">
      <label for="category-filter">分类筛选：</label>
      <select id="category-filter" class="select-input" onchange="filterByCategory(this.value)">
        <option value="">全部分类</option>
        <% if (typeof categories !== 'undefined') { %>
          <% categories.forEach(function(cat) { %>
            <option value="<%= cat %>" <%= typeof currentCategory !== 'undefined' && currentCategory === cat ? 'selected' : '' %>>
              <%= cat %>
            </option>
          <% }); %>
        <% } %>
      </select>
    </div>
    <div class="filter-group">
      <label for="sort-select">排序：</label>
      <select id="sort-select" class="select-input" onchange="sortProducts(this.value)">
        <option value="default">默认排序</option>
        <option value="price_asc">价格从低到高</option>
        <option value="price_desc">价格从高到低</option>
        <option value="name_asc">名称 A-Z</option>
      </select>
    </div>
  </div>

  <!-- ===== 商品网格 ===== -->
  <div class="product-grid" id="products-grid">
    <% if (typeof products !== 'undefined' && products.length > 0) { %>
      <% products.forEach(function(product) { %>
        <div class="product-card" data-category="<%= product.category %>">
          <a href="/products/<%= product.id %>">
            <div class="product-image">
              <img src="<%= product.image_url || '/static/images/placeholder.png' %>"
                   alt="<%= product.name %>"
                   loading="lazy">
            </div>
            <div class="product-info">
              <h3 class="product-name"><%= product.name %></h3>
              <p class="product-category"><%= product.category %></p>
              <p class="product-price">&yen;<%= product.price %></p>
            </div>
          </a>
          <!-- 快速加购按钮 -->
          <button class="btn btn-sm btn-add-cart"
                  onclick="event.preventDefault(); addToCart(<%= product.id %>, 1)">
            加入购物车
          </button>
        </div>
      <% }); %>
    <% } else { %>
      <p class="empty-state">该分类下暂无商品。</p>
    <% } %>
  </div>

  <!-- ===== 分页控件 ===== -->
  <% if (typeof pagination !== 'undefined' && pagination.totalPages > 1) { %>
    <div class="pagination">
      <!-- 上一页 -->
      <% if (pagination.currentPage > 1) { %>
        <a href="/products?page=<%= pagination.currentPage - 1 %><%= typeof currentCategory !== 'undefined' && currentCategory ? '&category=' + currentCategory : '' %>"
           class="pagination-link">
          &laquo; 上一页
        </a>
      <% } else { %>
        <span class="pagination-link disabled">&laquo; 上一页</span>
      <% } %>

      <!-- 页码 -->
      <% for (var i = 1; i <= pagination.totalPages; i++) { %>
        <a href="/products?page=<%= i %><%= typeof currentCategory !== 'undefined' && currentCategory ? '&category=' + currentCategory : '' %>"
           class="pagination-link<%= i === pagination.currentPage ? ' active' : '' %>">
          <%= i %>
        </a>
      <% } %>

      <!-- 下一页 -->
      <% if (pagination.currentPage < pagination.totalPages) { %>
        <a href="/products?page=<%= pagination.currentPage + 1 %><%= typeof currentCategory !== 'undefined' && currentCategory ? '&category=' + currentCategory : '' %>"
           class="pagination-link">
          下一页 &raquo;
        </a>
      <% } else { %>
        <span class="pagination-link disabled">下一页 &raquo;</span>
      <% } %>
    </div>
  <% } %>
</section>
```

#### Step 10.4: 创建 `app/views/product-detail.ejs` — 商品详情

- [ ] 创建文件 `app/views/product-detail.ejs`，展示商品图片、名称、价格、描述和加购按钮

```ejs
<% layout('layout') -%>

<section class="section">
  <!-- 面包屑导航 -->
  <nav class="breadcrumb">
    <a href="/">首页</a>
    <span class="separator">/</span>
    <a href="/products">商品列表</a>
    <span class="separator">/</span>
    <% if (typeof product !== 'undefined') { %>
      <span class="current"><%= product.name %></span>
    <% } %>
  </nav>

  <% if (typeof product !== 'undefined' && product) { %>
    <div class="product-detail">
      <!-- 商品图片 -->
      <div class="product-detail-image">
        <img src="<%= product.image_url || '/static/images/placeholder.png' %>"
             alt="<%= product.name %>"
             id="product-main-image">
      </div>

      <!-- 商品信息 -->
      <div class="product-detail-info">
        <h1 class="product-detail-name"><%= product.name %></h1>

        <p class="product-detail-category">
          分类：<a href="/products?category=<%= product.category %>"><%= product.category %></a>
        </p>

        <p class="product-detail-price">&yen;<%= product.price %></p>

        <div class="product-detail-desc">
          <h3>商品描述</h3>
          <p><%= product.description || '暂无描述信息。' %></p>
        </div>

        <!-- 数量选择 + 加入购物车 -->
        <div class="product-detail-actions">
          <div class="quantity-selector">
            <button class="btn btn-quantity" onclick="changeQuantity(-1)">-</button>
            <input type="number" id="product-quantity" value="1" min="1" max="99" class="quantity-input">
            <button class="btn btn-quantity" onclick="changeQuantity(1)">+</button>
          </div>
          <button class="btn btn-primary btn-add-cart-large"
                  onclick="addToCart(<%= product.id %>, getQuantity())">
            加入购物车
          </button>
        </div>

        <!-- 商品 ID（调试用） -->
        <p class="product-meta">商品 ID: <%= product.id %></p>
      </div>
    </div>
  <% } else { %>
    <div class="empty-state">
      <h2>商品不存在</h2>
      <p>请返回<a href="/products">商品列表</a>重新选择。</p>
    </div>
  <% } %>
</section>
```

#### Step 10.5: 创建 `app/views/cart.ejs` — 购物车

- [ ] 创建文件 `app/views/cart.ejs`，展示购物车商品列表、数量调整、总价和下单按钮

```ejs
<% layout('layout') -%>

<section class="section">
  <h1 class="page-title">购物车</h1>

  <!-- 购物车内容（JS 动态渲染） -->
  <div id="cart-container">
    <!-- 加载中状态 -->
    <div id="cart-loading" class="loading-state">
      <p>加载购物车...</p>
    </div>

    <!-- 空购物车提示（默认隐藏） -->
    <div id="cart-empty" class="empty-state" style="display:none;">
      <h2>购物车是空的</h2>
      <p>快去<a href="/products">挑选商品</a>吧！</p>
    </div>

    <!-- 购物车表格（默认隐藏，JS 填充） -->
    <div id="cart-content" style="display:none;">
      <table class="cart-table">
        <thead>
          <tr>
            <th class="cart-col-product">商品</th>
            <th class="cart-col-price">单价</th>
            <th class="cart-col-quantity">数量</th>
            <th class="cart-col-subtotal">小计</th>
            <th class="cart-col-action">操作</th>
          </tr>
        </thead>
        <tbody id="cart-items">
          <!-- JS 动态插入行 -->
        </tbody>
      </table>

      <!-- 总价与下单 -->
      <div class="cart-summary">
        <div class="cart-total">
          <span>总计：</span>
          <span class="cart-total-price" id="cart-total-price">&yen;0.00</span>
        </div>
        <div class="cart-actions">
          <a href="/products" class="btn btn-secondary">继续购物</a>
          <button class="btn btn-primary" onclick="placeOrder()" id="btn-place-order">
            提交订单
          </button>
        </div>
      </div>
    </div>
  </div>
</section>
```

#### Step 10.6: 创建 `app/views/login.ejs` — 登录/注册

- [ ] 创建文件 `app/views/login.ejs`，包含登录和注册两个 tab 切换的表单

```ejs
<% layout('layout') -%>

<section class="section">
  <div class="auth-container">
    <h1 class="page-title">用户中心</h1>

    <!-- ===== Tab 切换 ===== -->
    <div class="auth-tabs">
      <button class="auth-tab active" id="tab-login" onclick="switchTab('login')">登录</button>
      <button class="auth-tab" id="tab-register" onclick="switchTab('register')">注册</button>
    </div>

    <!-- ===== 登录表单 ===== -->
    <div class="auth-form" id="form-login">
      <form onsubmit="handleLogin(event)">
        <div class="form-group">
          <label for="login-email">邮箱</label>
          <input type="email" id="login-email" class="form-input"
                 placeholder="请输入邮箱" required autocomplete="email">
        </div>
        <div class="form-group">
          <label for="login-password">密码</label>
          <input type="password" id="login-password" class="form-input"
                 placeholder="请输入密码" required autocomplete="current-password">
        </div>
        <!-- 错误/成功消息 -->
        <div id="login-message" class="form-message" style="display:none;"></div>
        <button type="submit" class="btn btn-primary btn-full" id="btn-login">登录</button>
      </form>
    </div>

    <!-- ===== 注册表单 ===== -->
    <div class="auth-form" id="form-register" style="display:none;">
      <form onsubmit="handleRegister(event)">
        <div class="form-group">
          <label for="register-email">邮箱</label>
          <input type="email" id="register-email" class="form-input"
                 placeholder="请输入邮箱" required autocomplete="email">
        </div>
        <div class="form-group">
          <label for="register-password">密码</label>
          <input type="password" id="register-password" class="form-input"
                 placeholder="至少8位，含大小写字母和数字" required
                 minlength="8" autocomplete="new-password">
        </div>
        <div class="form-group">
          <label for="register-password-confirm">确认密码</label>
          <input type="password" id="register-password-confirm" class="form-input"
                 placeholder="再次输入密码" required autocomplete="new-password">
        </div>
        <!-- 错误/成功消息 -->
        <div id="register-message" class="form-message" style="display:none;"></div>
        <button type="submit" class="btn btn-primary btn-full" id="btn-register">注册</button>
      </form>
    </div>

    <!-- ===== 已登录状态 ===== -->
    <div class="auth-profile" id="user-profile" style="display:none;">
      <h2>欢迎回来</h2>
      <div class="profile-info">
        <p><strong>邮箱：</strong><span id="profile-email">-</span></p>
        <p><strong>Trace ID：</strong><span id="profile-trace-id">-</span></p>
      </div>
      <button class="btn btn-secondary btn-full" onclick="handleLogout()">退出登录</button>
    </div>
  </div>
</section>
```

#### Step 10.7: 创建 `app/views/debug.ejs` — 调试页

- [ ] 创建文件 `app/views/debug.ejs`，以表格形式展示所有 HTTP headers、cookies 和 trace-id

```ejs
<% layout('layout') -%>

<section class="section">
  <h1 class="page-title">调试信息</h1>
  <p class="page-desc">此页面展示 CloudFront 透传到 Express 的完整 HTTP 请求信息，用于验证 Header 注入、Cookie 转发和链路追踪。</p>

  <!-- ===== Trace ID 高亮显示 ===== -->
  <div class="debug-highlight">
    <h2>链路追踪</h2>
    <div class="debug-trace-box">
      <span class="debug-label">X-Trace-Id:</span>
      <code class="debug-value" id="debug-trace-id"><%= typeof traceId !== 'undefined' ? traceId : '(未获取)' %></code>
    </div>
    <% if (typeof isNewUser !== 'undefined' && isNewUser) { %>
      <p class="debug-note">* 首次访问，已生成新 UUID</p>
    <% } %>
  </div>

  <!-- ===== Request Headers 表格 ===== -->
  <div class="debug-section">
    <h2>Request Headers
      <span class="debug-count">
        (<%= typeof headers !== 'undefined' ? Object.keys(headers).length : 0 %> 项)
      </span>
    </h2>
    <table class="debug-table">
      <thead>
        <tr>
          <th class="debug-col-name">Header 名称</th>
          <th class="debug-col-value">值</th>
        </tr>
      </thead>
      <tbody>
        <% if (typeof headers !== 'undefined') { %>
          <% Object.keys(headers).sort().forEach(function(key) { %>
            <tr class="<%= key.startsWith('cloudfront') || key.startsWith('x-amz') || key === 'x-forwarded-for' || key === 'x-ab-group' ? 'debug-row-highlight' : '' %>">
              <td class="debug-header-name"><%= key %></td>
              <td class="debug-header-value"><code><%= headers[key] %></code></td>
            </tr>
          <% }); %>
        <% } %>
      </tbody>
    </table>
  </div>

  <!-- ===== Cookies 表格 ===== -->
  <div class="debug-section">
    <h2>Cookies
      <span class="debug-count">
        (<%= typeof cookies !== 'undefined' ? Object.keys(cookies).length : 0 %> 项)
      </span>
    </h2>
    <% if (typeof cookies !== 'undefined' && Object.keys(cookies).length > 0) { %>
      <table class="debug-table">
        <thead>
          <tr>
            <th class="debug-col-name">Cookie 名称</th>
            <th class="debug-col-value">值</th>
          </tr>
        </thead>
        <tbody>
          <% Object.keys(cookies).sort().forEach(function(key) { %>
            <tr class="<%= key === 'x-trace-id' || key === 'aws-waf-token' || key === 'x-ab-group' ? 'debug-row-highlight' : '' %>">
              <td class="debug-header-name"><%= key %></td>
              <td class="debug-header-value"><code><%= cookies[key] %></code></td>
            </tr>
          <% }); %>
        </tbody>
      </table>
    <% } else { %>
      <p class="empty-state">当前请求未携带任何 Cookie。</p>
    <% } %>
  </div>

  <!-- ===== 请求元信息 ===== -->
  <div class="debug-section">
    <h2>请求元信息</h2>
    <table class="debug-table">
      <tbody>
        <tr>
          <td class="debug-header-name">请求方法</td>
          <td class="debug-header-value"><code><%= typeof method !== 'undefined' ? method : '-' %></code></td>
        </tr>
        <tr>
          <td class="debug-header-name">请求 URL</td>
          <td class="debug-header-value"><code><%= typeof originalUrl !== 'undefined' ? originalUrl : '-' %></code></td>
        </tr>
        <tr>
          <td class="debug-header-name">协议</td>
          <td class="debug-header-value"><code><%= typeof protocol !== 'undefined' ? protocol : '-' %></code></td>
        </tr>
        <tr>
          <td class="debug-header-name">主机名</td>
          <td class="debug-header-value"><code><%= typeof hostname !== 'undefined' ? hostname : '-' %></code></td>
        </tr>
        <tr>
          <td class="debug-header-name">客户端 IP</td>
          <td class="debug-header-value"><code><%= typeof clientIp !== 'undefined' ? clientIp : '-' %></code></td>
        </tr>
        <tr>
          <td class="debug-header-name">时间戳</td>
          <td class="debug-header-value"><code><%= new Date().toISOString() %></code></td>
        </tr>
      </tbody>
    </table>
  </div>

  <!-- ===== JSON 原始数据（折叠） ===== -->
  <div class="debug-section">
    <details>
      <summary class="debug-toggle">查看原始 JSON 数据</summary>
      <pre class="debug-json"><code id="debug-raw-json"><%= typeof headers !== 'undefined' ? JSON.stringify({ headers: headers, cookies: cookies || {}, traceId: traceId || '' }, null, 2) : '{}' %></code></pre>
    </details>
  </div>
</section>
```

#### Step 10.8: 创建 `app/public/css/style.css` — 全局样式

- [ ] 创建文件 `app/public/css/style.css`，包含导航栏、商品卡片、表单、调试页、响应式网格等完整样式

```css
/* =============================================================================
 * Unice Demo - CloudFront 全功能演示平台 全局样式
 * =============================================================================
 * 设计原则：简洁功能性风格，深色导航栏，浅色内容区，响应式网格布局
 * ============================================================================= */

/* ── CSS 变量 ──────────────────────────────────────────────────────────────── */
:root {
  /* 主色调 */
  --color-primary: #1a73e8;        /* 蓝色主色（链接、按钮） */
  --color-primary-dark: #1557b0;   /* 深蓝（悬停状态） */
  --color-primary-light: #e8f0fe;  /* 浅蓝（选中背景） */

  /* 导航栏 */
  --color-nav-bg: #1a1a2e;         /* 深色导航背景 */
  --color-nav-text: #e0e0e0;       /* 导航文字 */
  --color-nav-hover: #ffffff;      /* 导航悬停 */
  --color-nav-active: #4fc3f7;     /* 导航当前页高亮 */

  /* 文字 */
  --color-text: #333333;           /* 正文文字 */
  --color-text-light: #666666;     /* 次要文字 */
  --color-text-muted: #999999;     /* 弱化文字 */

  /* 背景 */
  --color-bg: #f5f7fa;             /* 页面背景 */
  --color-bg-white: #ffffff;       /* 卡片/表单背景 */
  --color-bg-alt: #eef2f7;         /* 交替区域背景 */

  /* 边框 */
  --color-border: #e0e0e0;
  --color-border-light: #f0f0f0;

  /* 状态色 */
  --color-success: #34a853;
  --color-error: #ea4335;
  --color-warning: #fbbc04;
  --color-info: #4285f4;

  /* 价格 */
  --color-price: #e53935;

  /* 间距 */
  --spacing-xs: 4px;
  --spacing-sm: 8px;
  --spacing-md: 16px;
  --spacing-lg: 24px;
  --spacing-xl: 32px;
  --spacing-2xl: 48px;

  /* 圆角 */
  --radius-sm: 4px;
  --radius-md: 8px;
  --radius-lg: 12px;

  /* 阴影 */
  --shadow-sm: 0 1px 3px rgba(0, 0, 0, 0.1);
  --shadow-md: 0 4px 12px rgba(0, 0, 0, 0.1);
  --shadow-lg: 0 8px 24px rgba(0, 0, 0, 0.12);

  /* 容器宽度 */
  --container-max: 1200px;

  /* 字体 */
  --font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
                 'Helvetica Neue', Arial, 'Noto Sans SC', sans-serif;
  --font-mono: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
}

/* ── Reset & Base ──────────────────────────────────────────────────────────── */
*,
*::before,
*::after {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

html {
  font-size: 16px;
  scroll-behavior: smooth;
}

body {
  font-family: var(--font-family);
  color: var(--color-text);
  background-color: var(--color-bg);
  line-height: 1.6;
  min-height: 100vh;
  display: flex;
  flex-direction: column;
}

a {
  color: var(--color-primary);
  text-decoration: none;
  transition: color 0.2s;
}

a:hover {
  color: var(--color-primary-dark);
}

img {
  max-width: 100%;
  height: auto;
  display: block;
}

/* ── 导航栏 ────────────────────────────────────────────────────────────────── */
.navbar {
  background-color: var(--color-nav-bg);
  position: sticky;
  top: 0;
  z-index: 1000;
  box-shadow: var(--shadow-md);
}

.nav-container {
  max-width: var(--container-max);
  margin: 0 auto;
  padding: 0 var(--spacing-lg);
  display: flex;
  align-items: center;
  justify-content: space-between;
  height: 60px;
}

.nav-brand {
  font-size: 1.25rem;
  font-weight: 700;
  color: var(--color-nav-hover);
  letter-spacing: 0.5px;
}

.nav-brand:hover {
  color: var(--color-nav-active);
}

.nav-links {
  list-style: none;
  display: flex;
  gap: var(--spacing-lg);
  align-items: center;
}

.nav-link {
  color: var(--color-nav-text);
  font-size: 0.95rem;
  padding: var(--spacing-sm) 0;
  border-bottom: 2px solid transparent;
  transition: color 0.2s, border-color 0.2s;
  position: relative;
}

.nav-link:hover {
  color: var(--color-nav-hover);
}

.nav-link.active {
  color: var(--color-nav-active);
  border-bottom-color: var(--color-nav-active);
}

/* 购物车徽章 */
.badge {
  background-color: var(--color-error);
  color: #fff;
  font-size: 0.7rem;
  padding: 1px 6px;
  border-radius: 10px;
  position: absolute;
  top: -8px;
  right: -14px;
  min-width: 18px;
  text-align: center;
}

/* 移动端菜单按钮 */
.nav-toggle {
  display: none;
  flex-direction: column;
  gap: 5px;
  background: none;
  border: none;
  cursor: pointer;
  padding: var(--spacing-sm);
}

.nav-toggle span {
  display: block;
  width: 24px;
  height: 2px;
  background-color: var(--color-nav-text);
  transition: transform 0.3s, opacity 0.3s;
}

/* ── 主内容区 ──────────────────────────────────────────────────────────────── */
.main-content {
  flex: 1;
}

.section {
  max-width: var(--container-max);
  margin: 0 auto;
  padding: var(--spacing-2xl) var(--spacing-lg);
}

.section-alt {
  background-color: var(--color-bg-alt);
  max-width: 100%;
  padding-left: calc((100% - var(--container-max)) / 2 + var(--spacing-lg));
  padding-right: calc((100% - var(--container-max)) / 2 + var(--spacing-lg));
}

.section-title {
  font-size: 1.5rem;
  font-weight: 600;
  margin-bottom: var(--spacing-xl);
  color: var(--color-text);
}

.page-title {
  font-size: 1.75rem;
  font-weight: 700;
  margin-bottom: var(--spacing-lg);
}

.page-desc {
  color: var(--color-text-light);
  margin-bottom: var(--spacing-xl);
  line-height: 1.8;
}

/* ── Hero Banner ───────────────────────────────────────────────────────────── */
.hero {
  background: linear-gradient(135deg, var(--color-nav-bg) 0%, #16213e 100%);
  color: #fff;
  padding: var(--spacing-2xl) var(--spacing-lg);
  text-align: center;
  max-width: 100%;
}

.hero-content {
  max-width: var(--container-max);
  margin: 0 auto;
  padding: var(--spacing-2xl) 0;
}

.hero h1 {
  font-size: 2rem;
  margin-bottom: var(--spacing-md);
}

.hero p {
  font-size: 1.1rem;
  color: #b0bec5;
  margin-bottom: var(--spacing-xl);
  max-width: 700px;
  margin-left: auto;
  margin-right: auto;
  line-height: 1.8;
}

/* ── 商品网格 ──────────────────────────────────────────────────────────────── */
.product-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
  gap: var(--spacing-lg);
}

.product-card {
  background: var(--color-bg-white);
  border-radius: var(--radius-md);
  overflow: hidden;
  box-shadow: var(--shadow-sm);
  transition: transform 0.2s, box-shadow 0.2s;
  display: flex;
  flex-direction: column;
}

.product-card:hover {
  transform: translateY(-4px);
  box-shadow: var(--shadow-lg);
}

.product-card a {
  text-decoration: none;
  color: inherit;
  flex: 1;
}

.product-image {
  width: 100%;
  height: 200px;
  overflow: hidden;
  background-color: var(--color-bg-alt);
  display: flex;
  align-items: center;
  justify-content: center;
}

.product-image img {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.product-info {
  padding: var(--spacing-md);
}

.product-name {
  font-size: 1rem;
  font-weight: 600;
  margin-bottom: var(--spacing-xs);
  /* 最多两行，超出省略 */
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}

.product-category {
  font-size: 0.85rem;
  color: var(--color-text-muted);
  margin-bottom: var(--spacing-sm);
}

.product-price {
  font-size: 1.1rem;
  font-weight: 700;
  color: var(--color-price);
}

/* 快速加购按钮 */
.btn-add-cart {
  margin: 0 var(--spacing-md) var(--spacing-md);
}

/* ── 功能特性网格 ──────────────────────────────────────────────────────────── */
.feature-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
  gap: var(--spacing-lg);
}

.feature-card {
  background: var(--color-bg-white);
  padding: var(--spacing-xl);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
}

.feature-card h3 {
  font-size: 1.1rem;
  color: var(--color-primary);
  margin-bottom: var(--spacing-sm);
}

.feature-card p {
  font-size: 0.9rem;
  color: var(--color-text-light);
  line-height: 1.7;
}

/* ── 筛选栏 ────────────────────────────────────────────────────────────────── */
.filter-bar {
  display: flex;
  gap: var(--spacing-lg);
  margin-bottom: var(--spacing-xl);
  flex-wrap: wrap;
  align-items: center;
}

.filter-group {
  display: flex;
  align-items: center;
  gap: var(--spacing-sm);
}

.filter-group label {
  font-size: 0.9rem;
  color: var(--color-text-light);
  white-space: nowrap;
}

.select-input {
  padding: var(--spacing-sm) var(--spacing-md);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: 0.9rem;
  background: var(--color-bg-white);
  cursor: pointer;
}

.select-input:focus {
  outline: none;
  border-color: var(--color-primary);
  box-shadow: 0 0 0 2px var(--color-primary-light);
}

/* ── 分页 ──────────────────────────────────────────────────────────────────── */
.pagination {
  display: flex;
  justify-content: center;
  gap: var(--spacing-sm);
  margin-top: var(--spacing-xl);
  flex-wrap: wrap;
}

.pagination-link {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 36px;
  height: 36px;
  padding: 0 var(--spacing-sm);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: 0.9rem;
  color: var(--color-text);
  background: var(--color-bg-white);
  transition: all 0.2s;
}

.pagination-link:hover:not(.disabled):not(.active) {
  border-color: var(--color-primary);
  color: var(--color-primary);
}

.pagination-link.active {
  background-color: var(--color-primary);
  border-color: var(--color-primary);
  color: #fff;
}

.pagination-link.disabled {
  color: var(--color-text-muted);
  cursor: not-allowed;
}

/* ── 商品详情页 ────────────────────────────────────────────────────────────── */
.breadcrumb {
  font-size: 0.9rem;
  color: var(--color-text-muted);
  margin-bottom: var(--spacing-xl);
}

.breadcrumb a {
  color: var(--color-text-light);
}

.breadcrumb a:hover {
  color: var(--color-primary);
}

.breadcrumb .separator {
  margin: 0 var(--spacing-sm);
}

.breadcrumb .current {
  color: var(--color-text);
}

.product-detail {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: var(--spacing-2xl);
  align-items: start;
}

.product-detail-image {
  background: var(--color-bg-white);
  border-radius: var(--radius-md);
  overflow: hidden;
  box-shadow: var(--shadow-sm);
}

.product-detail-image img {
  width: 100%;
  height: auto;
  min-height: 300px;
  object-fit: cover;
}

.product-detail-info {
  padding: var(--spacing-md) 0;
}

.product-detail-name {
  font-size: 1.75rem;
  font-weight: 700;
  margin-bottom: var(--spacing-md);
}

.product-detail-category {
  font-size: 0.95rem;
  color: var(--color-text-light);
  margin-bottom: var(--spacing-md);
}

.product-detail-price {
  font-size: 1.5rem;
  font-weight: 700;
  color: var(--color-price);
  margin-bottom: var(--spacing-xl);
}

.product-detail-desc {
  margin-bottom: var(--spacing-xl);
}

.product-detail-desc h3 {
  font-size: 1rem;
  margin-bottom: var(--spacing-sm);
  color: var(--color-text);
}

.product-detail-desc p {
  color: var(--color-text-light);
  line-height: 1.8;
}

.product-detail-actions {
  display: flex;
  gap: var(--spacing-md);
  align-items: center;
  margin-bottom: var(--spacing-xl);
}

.quantity-selector {
  display: flex;
  align-items: center;
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  overflow: hidden;
}

.btn-quantity {
  width: 36px;
  height: 36px;
  border: none;
  background: var(--color-bg-alt);
  font-size: 1.1rem;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;
  transition: background 0.2s;
}

.btn-quantity:hover {
  background: var(--color-border);
}

.quantity-input {
  width: 50px;
  height: 36px;
  border: none;
  border-left: 1px solid var(--color-border);
  border-right: 1px solid var(--color-border);
  text-align: center;
  font-size: 0.95rem;
  -moz-appearance: textfield;
}

.quantity-input::-webkit-outer-spin-button,
.quantity-input::-webkit-inner-spin-button {
  -webkit-appearance: none;
}

.product-meta {
  font-size: 0.8rem;
  color: var(--color-text-muted);
}

/* ── 购物车表格 ────────────────────────────────────────────────────────────── */
.cart-table {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-bg-white);
  border-radius: var(--radius-md);
  overflow: hidden;
  box-shadow: var(--shadow-sm);
}

.cart-table thead {
  background: var(--color-bg-alt);
}

.cart-table th {
  padding: var(--spacing-md);
  text-align: left;
  font-size: 0.9rem;
  font-weight: 600;
  color: var(--color-text-light);
}

.cart-table td {
  padding: var(--spacing-md);
  border-top: 1px solid var(--color-border-light);
  font-size: 0.95rem;
  vertical-align: middle;
}

.cart-col-product { width: 40%; }
.cart-col-price { width: 15%; }
.cart-col-quantity { width: 20%; }
.cart-col-subtotal { width: 15%; }
.cart-col-action { width: 10%; }

.cart-item-name {
  font-weight: 500;
}

.cart-item-remove {
  color: var(--color-error);
  cursor: pointer;
  font-size: 0.85rem;
  background: none;
  border: none;
  padding: var(--spacing-xs) var(--spacing-sm);
}

.cart-item-remove:hover {
  text-decoration: underline;
}

.cart-summary {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-top: var(--spacing-xl);
  padding: var(--spacing-lg);
  background: var(--color-bg-white);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
  flex-wrap: wrap;
  gap: var(--spacing-md);
}

.cart-total {
  font-size: 1.25rem;
}

.cart-total-price {
  font-weight: 700;
  color: var(--color-price);
  font-size: 1.5rem;
}

.cart-actions {
  display: flex;
  gap: var(--spacing-md);
}

/* ── 登录/注册 ─────────────────────────────────────────────────────────────── */
.auth-container {
  max-width: 420px;
  margin: 0 auto;
}

.auth-tabs {
  display: flex;
  margin-bottom: var(--spacing-xl);
  border-bottom: 2px solid var(--color-border);
}

.auth-tab {
  flex: 1;
  padding: var(--spacing-md);
  font-size: 1rem;
  font-weight: 500;
  border: none;
  background: none;
  cursor: pointer;
  color: var(--color-text-light);
  border-bottom: 2px solid transparent;
  margin-bottom: -2px;
  transition: color 0.2s, border-color 0.2s;
}

.auth-tab:hover {
  color: var(--color-text);
}

.auth-tab.active {
  color: var(--color-primary);
  border-bottom-color: var(--color-primary);
}

.auth-form {
  background: var(--color-bg-white);
  padding: var(--spacing-xl);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
}

.form-group {
  margin-bottom: var(--spacing-lg);
}

.form-group label {
  display: block;
  font-size: 0.9rem;
  font-weight: 500;
  margin-bottom: var(--spacing-sm);
  color: var(--color-text);
}

.form-input {
  width: 100%;
  padding: var(--spacing-sm) var(--spacing-md);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  font-size: 0.95rem;
  line-height: 1.6;
  transition: border-color 0.2s, box-shadow 0.2s;
}

.form-input:focus {
  outline: none;
  border-color: var(--color-primary);
  box-shadow: 0 0 0 2px var(--color-primary-light);
}

.form-message {
  padding: var(--spacing-sm) var(--spacing-md);
  border-radius: var(--radius-sm);
  font-size: 0.9rem;
  margin-bottom: var(--spacing-md);
}

.form-message.success {
  background-color: #e8f5e9;
  color: var(--color-success);
  border: 1px solid #c8e6c9;
}

.form-message.error {
  background-color: #ffebee;
  color: var(--color-error);
  border: 1px solid #ffcdd2;
}

.auth-profile {
  background: var(--color-bg-white);
  padding: var(--spacing-xl);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
  text-align: center;
}

.auth-profile h2 {
  margin-bottom: var(--spacing-lg);
}

.profile-info {
  text-align: left;
  margin-bottom: var(--spacing-xl);
}

.profile-info p {
  padding: var(--spacing-sm) 0;
  border-bottom: 1px solid var(--color-border-light);
  font-size: 0.95rem;
}

/* ── 调试页 ────────────────────────────────────────────────────────────────── */
.debug-highlight {
  background: var(--color-bg-white);
  padding: var(--spacing-xl);
  border-radius: var(--radius-md);
  box-shadow: var(--shadow-sm);
  margin-bottom: var(--spacing-xl);
  border-left: 4px solid var(--color-primary);
}

.debug-highlight h2 {
  font-size: 1.1rem;
  margin-bottom: var(--spacing-md);
}

.debug-trace-box {
  display: flex;
  align-items: center;
  gap: var(--spacing-md);
  flex-wrap: wrap;
}

.debug-label {
  font-weight: 600;
  font-size: 0.95rem;
}

.debug-value {
  font-family: var(--font-mono);
  font-size: 0.95rem;
  background: var(--color-bg-alt);
  padding: var(--spacing-xs) var(--spacing-sm);
  border-radius: var(--radius-sm);
  word-break: break-all;
}

.debug-note {
  margin-top: var(--spacing-sm);
  font-size: 0.85rem;
  color: var(--color-info);
}

.debug-section {
  margin-bottom: var(--spacing-xl);
}

.debug-section h2 {
  font-size: 1.1rem;
  margin-bottom: var(--spacing-md);
}

.debug-count {
  font-weight: 400;
  font-size: 0.85rem;
  color: var(--color-text-muted);
}

.debug-table {
  width: 100%;
  border-collapse: collapse;
  background: var(--color-bg-white);
  border-radius: var(--radius-md);
  overflow: hidden;
  box-shadow: var(--shadow-sm);
  font-size: 0.9rem;
}

.debug-table th {
  background: var(--color-bg-alt);
  padding: var(--spacing-sm) var(--spacing-md);
  text-align: left;
  font-weight: 600;
  font-size: 0.85rem;
  color: var(--color-text-light);
}

.debug-table td {
  padding: var(--spacing-sm) var(--spacing-md);
  border-top: 1px solid var(--color-border-light);
  vertical-align: top;
}

.debug-col-name { width: 30%; }
.debug-col-value { width: 70%; }

.debug-header-name {
  font-weight: 500;
  font-family: var(--font-mono);
  font-size: 0.85rem;
}

.debug-header-value code {
  font-family: var(--font-mono);
  font-size: 0.85rem;
  word-break: break-all;
}

/* CloudFront / AWS 相关 Header 行高亮 */
.debug-row-highlight {
  background-color: #fffde7;
}

.debug-toggle {
  cursor: pointer;
  font-weight: 500;
  color: var(--color-primary);
  padding: var(--spacing-sm) 0;
}

.debug-json {
  background: var(--color-nav-bg);
  color: #a5d6a7;
  padding: var(--spacing-md);
  border-radius: var(--radius-sm);
  overflow-x: auto;
  font-size: 0.85rem;
  line-height: 1.5;
  margin-top: var(--spacing-sm);
}

/* ── 按钮 ──────────────────────────────────────────────────────────────────── */
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: var(--spacing-sm) var(--spacing-lg);
  font-size: 0.95rem;
  font-weight: 500;
  border: 1px solid transparent;
  border-radius: var(--radius-sm);
  cursor: pointer;
  transition: all 0.2s;
  text-decoration: none;
  line-height: 1.5;
}

.btn-primary {
  background-color: var(--color-primary);
  color: #fff;
}

.btn-primary:hover {
  background-color: var(--color-primary-dark);
  color: #fff;
}

.btn-secondary {
  background-color: var(--color-bg-white);
  color: var(--color-text);
  border-color: var(--color-border);
}

.btn-secondary:hover {
  background-color: var(--color-bg-alt);
  color: var(--color-text);
}

.btn-sm {
  padding: var(--spacing-xs) var(--spacing-md);
  font-size: 0.85rem;
}

.btn-full {
  width: 100%;
}

.btn-add-cart-large {
  padding: var(--spacing-md) var(--spacing-xl);
  font-size: 1rem;
}

.btn:disabled {
  opacity: 0.6;
  cursor: not-allowed;
}

/* ── 空状态 / 加载状态 ────────────────────────────────────────────────────── */
.empty-state {
  text-align: center;
  padding: var(--spacing-2xl);
  color: var(--color-text-light);
}

.empty-state h2 {
  font-size: 1.25rem;
  margin-bottom: var(--spacing-md);
  color: var(--color-text);
}

.loading-state {
  text-align: center;
  padding: var(--spacing-2xl);
  color: var(--color-text-muted);
}

/* ── 提示消息（Toast） ────────────────────────────────────────────────────── */
.toast-container {
  position: fixed;
  top: 76px;
  right: var(--spacing-lg);
  z-index: 2000;
  display: flex;
  flex-direction: column;
  gap: var(--spacing-sm);
}

.toast {
  padding: var(--spacing-md) var(--spacing-lg);
  border-radius: var(--radius-sm);
  font-size: 0.9rem;
  box-shadow: var(--shadow-md);
  animation: slideIn 0.3s ease;
  max-width: 360px;
}

.toast-success {
  background-color: var(--color-success);
  color: #fff;
}

.toast-error {
  background-color: var(--color-error);
  color: #fff;
}

.toast-info {
  background-color: var(--color-info);
  color: #fff;
}

@keyframes slideIn {
  from {
    transform: translateX(100%);
    opacity: 0;
  }
  to {
    transform: translateX(0);
    opacity: 1;
  }
}

/* ── Footer ────────────────────────────────────────────────────────────────── */
.footer {
  background-color: var(--color-nav-bg);
  color: var(--color-nav-text);
  padding: var(--spacing-xl) var(--spacing-lg);
  text-align: center;
  font-size: 0.85rem;
}

.footer-container {
  max-width: var(--container-max);
  margin: 0 auto;
}

.footer a {
  color: var(--color-nav-active);
}

.footer-sub {
  margin-top: var(--spacing-sm);
  color: var(--color-text-muted);
}

.footer-trace {
  margin-top: var(--spacing-sm);
  font-family: var(--font-mono);
  font-size: 0.8rem;
  color: var(--color-text-muted);
}

/* ── 响应式布局 ────────────────────────────────────────────────────────────── */

/* 平板 (<= 768px) */
@media (max-width: 768px) {
  /* 导航栏：折叠菜单 */
  .nav-toggle {
    display: flex;
  }

  .nav-links {
    display: none;
    position: absolute;
    top: 60px;
    left: 0;
    right: 0;
    background: var(--color-nav-bg);
    flex-direction: column;
    padding: var(--spacing-md) 0;
    box-shadow: var(--shadow-md);
  }

  .nav-links.open {
    display: flex;
  }

  .nav-link {
    padding: var(--spacing-md) var(--spacing-lg);
    border-bottom: none;
  }

  /* 商品详情：单列 */
  .product-detail {
    grid-template-columns: 1fr;
  }

  /* 购物车表格：紧凑 */
  .cart-table th,
  .cart-table td {
    padding: var(--spacing-sm);
    font-size: 0.85rem;
  }

  .cart-summary {
    flex-direction: column;
    text-align: center;
  }

  /* 筛选栏：堆叠 */
  .filter-bar {
    flex-direction: column;
    align-items: flex-start;
  }

  /* Hero */
  .hero h1 {
    font-size: 1.5rem;
  }
}

/* 手机 (<= 480px) */
@media (max-width: 480px) {
  .product-grid {
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: var(--spacing-md);
  }

  .product-image {
    height: 150px;
  }

  .product-detail-actions {
    flex-direction: column;
    align-items: stretch;
  }

  .section {
    padding: var(--spacing-lg) var(--spacing-md);
  }
}
```

#### Step 10.9: 创建 `app/public/js/main.js` — 前端逻辑

- [ ] 创建文件 `app/public/js/main.js`，包含购物车 AJAX 操作、登录 fetch 提交、JWT token 管理、UI 交互

```javascript
/* =============================================================================
 * Unice Demo - 前端 JavaScript
 * =============================================================================
 * 功能：购物车 AJAX 操作、登录/注册 fetch 提交、JWT token 管理、Toast 提示
 * 依赖：无外部框架，纯原生 fetch API
 * ============================================================================= */

'use strict';

// ── 全局配置 ──────────────────────────────────────────────────────────────────
var UniceDemoApp = (function () {

  // JWT token 存储键名
  var TOKEN_KEY = 'unice_access_token';
  var USER_KEY = 'unice_user_info';

  // ==========================================================================
  // 工具函数
  // ==========================================================================

  /**
   * 获取存储的 JWT token
   * @returns {string|null}
   */
  function getToken() {
    return localStorage.getItem(TOKEN_KEY);
  }

  /**
   * 保存 JWT token 到 localStorage
   * @param {string} token
   */
  function setToken(token) {
    localStorage.setItem(TOKEN_KEY, token);
  }

  /**
   * 清除 JWT token 和用户信息
   */
  function clearAuth() {
    localStorage.removeItem(TOKEN_KEY);
    localStorage.removeItem(USER_KEY);
  }

  /**
   * 获取用户信息
   * @returns {object|null}
   */
  function getUserInfo() {
    var data = localStorage.getItem(USER_KEY);
    if (data) {
      try { return JSON.parse(data); } catch (e) { return null; }
    }
    return null;
  }

  /**
   * 保存用户信息
   * @param {object} user
   */
  function setUserInfo(user) {
    localStorage.setItem(USER_KEY, JSON.stringify(user));
  }

  /**
   * 检查是否已登录
   * @returns {boolean}
   */
  function isLoggedIn() {
    return !!getToken();
  }

  /**
   * 带认证的 fetch 封装
   * @param {string} url
   * @param {object} options - fetch options
   * @returns {Promise<Response>}
   */
  function authFetch(url, options) {
    options = options || {};
    options.headers = options.headers || {};
    var token = getToken();
    if (token) {
      options.headers['Authorization'] = 'Bearer ' + token;
    }
    return fetch(url, options);
  }

  // ==========================================================================
  // Toast 提示
  // ==========================================================================

  /**
   * 显示 Toast 提示
   * @param {string} message - 消息文本
   * @param {string} type - 类型：'success' | 'error' | 'info'
   * @param {number} duration - 显示时长（毫秒），默认 3000
   */
  function showToast(message, type, duration) {
    type = type || 'info';
    duration = duration || 3000;

    // 确保 Toast 容器存在
    var container = document.querySelector('.toast-container');
    if (!container) {
      container = document.createElement('div');
      container.className = 'toast-container';
      document.body.appendChild(container);
    }

    // 创建 Toast 元素
    var toast = document.createElement('div');
    toast.className = 'toast toast-' + type;
    toast.textContent = message;
    container.appendChild(toast);

    // 自动移除
    setTimeout(function () {
      toast.style.opacity = '0';
      toast.style.transform = 'translateX(100%)';
      setTimeout(function () {
        if (toast.parentNode) toast.parentNode.removeChild(toast);
      }, 300);
    }, duration);
  }

  // ==========================================================================
  // 购物车操作
  // ==========================================================================

  /**
   * 加入购物车
   * 先查询商品信息（name, price），再 POST 到购物车 API
   * @param {number} productId - 商品 ID
   * @param {number} quantity - 数量
   */
  function addToCart(productId, quantity) {
    quantity = quantity || 1;

    // 先获取商品信息
    fetch('/api/products/' + productId)
    .then(function (res) { return res.json(); })
    .then(function (data) {
      if (data.error || !data.product) {
        showToast(data.error || '商品不存在', 'error');
        return;
      }

      var product = data.product;

      // 发送加购请求（包含完整商品信息）
      return authFetch('/api/cart', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          productId: String(product.id),
          name: product.name,
          price: product.price,
          quantity: quantity
        })
      });
    })
    .then(function (res) {
      if (!res) return;
      return res.json();
    })
    .then(function (data) {
      if (!data) return;
      if (data.error) {
        showToast(data.error, 'error');
        return;
      }
      showToast('已加入购物车', 'success');
      updateCartBadge(data.itemCount || 0);
    })
    .catch(function (err) {
      console.error('加入购物车失败:', err);
      showToast('操作失败，请稍后重试', 'error');
    });
  }

  /**
   * 加载购物车数据并渲染
   */
  function loadCart() {
    var loading = document.getElementById('cart-loading');
    var empty = document.getElementById('cart-empty');
    var content = document.getElementById('cart-content');
    var tbody = document.getElementById('cart-items');
    var totalEl = document.getElementById('cart-total-price');

    if (!loading) return; // 不在购物车页面

    authFetch('/api/cart')
      .then(function (res) { return res.json(); })
      .then(function (data) {
        loading.style.display = 'none';

        if (data.error === 'unauthorized') {
          // 未登录
          empty.style.display = 'block';
          empty.innerHTML = '<h2>请先登录</h2><p>登录后即可查看和管理购物车。<a href="/login">去登录</a></p>';
          return;
        }

        var items = data.items || [];
        if (items.length === 0) {
          empty.style.display = 'block';
          return;
        }

        // 渲染购物车项
        content.style.display = 'block';
        tbody.innerHTML = '';
        var total = 0;

        items.forEach(function (item) {
          var subtotal = (item.price * item.quantity).toFixed(2);
          total += parseFloat(subtotal);

          var tr = document.createElement('tr');
          tr.innerHTML =
            '<td class="cart-item-name">' + escapeHtml(item.name) + '</td>' +
            '<td>&yen;' + item.price + '</td>' +
            '<td>' +
              '<div class="quantity-selector">' +
                '<button class="btn-quantity" onclick="UniceDemoApp.updateCartItem(' + item.productId + ', ' + (item.quantity - 1) + ')">-</button>' +
                '<input type="number" value="' + item.quantity + '" min="1" max="99" class="quantity-input" ' +
                  'onchange="UniceDemoApp.updateCartItem(' + item.productId + ', parseInt(this.value))">' +
                '<button class="btn-quantity" onclick="UniceDemoApp.updateCartItem(' + item.productId + ', ' + (item.quantity + 1) + ')">+</button>' +
              '</div>' +
            '</td>' +
            '<td>&yen;' + subtotal + '</td>' +
            '<td><button class="cart-item-remove" onclick="UniceDemoApp.removeFromCart(' + item.productId + ')">删除</button></td>';
          tbody.appendChild(tr);
        });

        totalEl.textContent = '\u00A5' + total.toFixed(2);
        updateCartBadge(items.length);
      })
      .catch(function (err) {
        console.error('加载购物车失败:', err);
        loading.style.display = 'none';
        empty.style.display = 'block';
        empty.innerHTML = '<h2>加载失败</h2><p>请刷新页面重试。</p>';
      });
  }

  /**
   * 更新购物车商品数量
   * @param {number} productId
   * @param {number} newQuantity
   */
  function updateCartItem(productId, newQuantity) {
    if (newQuantity < 1) {
      removeFromCart(productId);
      return;
    }

    authFetch('/api/cart', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ productId: productId, quantity: newQuantity })
    })
    .then(function () { loadCart(); })
    .catch(function (err) {
      console.error('更新购物车失败:', err);
      showToast('操作失败', 'error');
    });
  }

  /**
   * 从购物车移除商品
   * @param {number} productId
   */
  function removeFromCart(productId) {
    authFetch('/api/cart?productId=' + productId, {
      method: 'DELETE'
    })
    .then(function () {
      showToast('已从购物车移除', 'info');
      loadCart();
    })
    .catch(function (err) {
      console.error('删除购物车商品失败:', err);
      showToast('操作失败', 'error');
    });
  }

  /**
   * 更新导航栏购物车徽章
   * @param {number} count
   */
  function updateCartBadge(count) {
    var badge = document.getElementById('cart-badge');
    if (!badge) return;
    if (count > 0) {
      badge.textContent = count;
      badge.style.display = 'inline-block';
    } else {
      badge.style.display = 'none';
    }
  }

  /**
   * 提交订单
   */
  function placeOrder() {
    var btn = document.getElementById('btn-place-order');
    if (btn) btn.disabled = true;

    authFetch('/api/orders', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' }
    })
    .then(function (res) { return res.json(); })
    .then(function (data) {
      if (btn) btn.disabled = false;
      if (data.error) {
        showToast(data.error, 'error');
        return;
      }
      showToast('订单提交成功！订单号: ' + (data.orderId || '-'), 'success', 5000);
      // 刷新购物车
      setTimeout(function () { loadCart(); }, 1000);
    })
    .catch(function (err) {
      if (btn) btn.disabled = false;
      console.error('提交订单失败:', err);
      showToast('提交失败，请稍后重试', 'error');
    });
  }

  // ==========================================================================
  // 登录 / 注册
  // ==========================================================================

  /**
   * 切换登录/注册 Tab
   * @param {string} tab - 'login' | 'register'
   */
  function switchTab(tab) {
    var tabLogin = document.getElementById('tab-login');
    var tabRegister = document.getElementById('tab-register');
    var formLogin = document.getElementById('form-login');
    var formRegister = document.getElementById('form-register');

    if (!tabLogin) return;

    if (tab === 'login') {
      tabLogin.classList.add('active');
      tabRegister.classList.remove('active');
      formLogin.style.display = 'block';
      formRegister.style.display = 'none';
    } else {
      tabRegister.classList.add('active');
      tabLogin.classList.remove('active');
      formRegister.style.display = 'block';
      formLogin.style.display = 'none';
    }
  }

  /**
   * 显示表单消息
   * @param {string} elementId
   * @param {string} message
   * @param {string} type - 'success' | 'error'
   */
  function showFormMessage(elementId, message, type) {
    var el = document.getElementById(elementId);
    if (!el) return;
    el.textContent = message;
    el.className = 'form-message ' + type;
    el.style.display = 'block';
  }

  /**
   * 处理登录表单提交
   * @param {Event} event
   */
  function handleLogin(event) {
    event.preventDefault();

    var email = document.getElementById('login-email').value.trim();
    var password = document.getElementById('login-password').value;
    var btn = document.getElementById('btn-login');

    if (!email || !password) {
      showFormMessage('login-message', '请填写邮箱和密码', 'error');
      return;
    }

    btn.disabled = true;
    btn.textContent = '登录中...';

    // 调用 Express 后端登录 API
    fetch('/api/user/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email, password: password })
    })
    .then(function (res) { return res.json(); })
    .then(function (data) {
      btn.disabled = false;
      btn.textContent = '登录';

      if (data.error) {
        showFormMessage('login-message', data.error, 'error');
        return;
      }

      // 保存 token 和用户信息
      if (data.accessToken) {
        setToken(data.accessToken);
      }
      if (data.user) {
        setUserInfo(data.user);
      }

      showFormMessage('login-message', '登录成功！', 'success');
      showToast('登录成功', 'success');

      // 更新页面状态
      updateAuthUI();
    })
    .catch(function (err) {
      btn.disabled = false;
      btn.textContent = '登录';
      console.error('登录失败:', err);
      showFormMessage('login-message', '网络错误，请稍后重试', 'error');
    });
  }

  /**
   * 处理注册表单提交
   * @param {Event} event
   */
  function handleRegister(event) {
    event.preventDefault();

    var email = document.getElementById('register-email').value.trim();
    var password = document.getElementById('register-password').value;
    var confirmPassword = document.getElementById('register-password-confirm').value;
    var btn = document.getElementById('btn-register');

    if (!email || !password) {
      showFormMessage('register-message', '请填写所有字段', 'error');
      return;
    }

    if (password !== confirmPassword) {
      showFormMessage('register-message', '两次输入的密码不一致', 'error');
      return;
    }

    if (password.length < 8) {
      showFormMessage('register-message', '密码长度至少 8 位', 'error');
      return;
    }

    btn.disabled = true;
    btn.textContent = '注册中...';

    // 调用 Express 后端注册 API
    fetch('/api/user/register', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email, password: password })
    })
    .then(function (res) { return res.json(); })
    .then(function (data) {
      btn.disabled = false;
      btn.textContent = '注册';

      if (data.error) {
        showFormMessage('register-message', data.error, 'error');
        return;
      }

      showFormMessage('register-message', '注册成功！请切换到登录标签页登录。', 'success');
      showToast('注册成功', 'success');
    })
    .catch(function (err) {
      btn.disabled = false;
      btn.textContent = '注册';
      console.error('注册失败:', err);
      showFormMessage('register-message', '网络错误，请稍后重试', 'error');
    });
  }

  /**
   * 退出登录
   */
  function handleLogout() {
    clearAuth();
    showToast('已退出登录', 'info');
    updateAuthUI();
  }

  /**
   * 更新登录/注册页面 UI（根据登录状态切换显示）
   */
  function updateAuthUI() {
    var formLogin = document.getElementById('form-login');
    var formRegister = document.getElementById('form-register');
    var profile = document.getElementById('user-profile');
    var tabs = document.querySelector('.auth-tabs');
    var loginLink = document.getElementById('nav-login-link');

    if (isLoggedIn()) {
      // 已登录：显示个人信息
      if (formLogin) formLogin.style.display = 'none';
      if (formRegister) formRegister.style.display = 'none';
      if (tabs) tabs.style.display = 'none';
      if (profile) {
        profile.style.display = 'block';
        var user = getUserInfo();
        if (user) {
          var emailEl = document.getElementById('profile-email');
          var traceEl = document.getElementById('profile-trace-id');
          if (emailEl) emailEl.textContent = user.email || '-';
          if (traceEl) traceEl.textContent = user.traceId || '-';
        }
      }
      // 导航栏更新
      if (loginLink) loginLink.textContent = '我的';
    } else {
      // 未登录：显示登录表单
      if (formLogin) formLogin.style.display = 'block';
      if (formRegister) formRegister.style.display = 'none';
      if (tabs) tabs.style.display = 'flex';
      if (profile) profile.style.display = 'none';
      if (loginLink) loginLink.textContent = 'Login';
    }
  }

  // ==========================================================================
  // 商品列表页辅助
  // ==========================================================================

  /**
   * 按分类筛选（页面跳转）
   * @param {string} category
   */
  function filterByCategory(category) {
    var url = '/products';
    if (category) {
      url += '?category=' + encodeURIComponent(category);
    }
    window.location.href = url;
  }

  /**
   * 按排序方式重新请求（页面跳转）
   * @param {string} sort
   */
  function sortProducts(sort) {
    var url = new URL(window.location.href);
    url.searchParams.set('sort', sort);
    window.location.href = url.toString();
  }

  // ==========================================================================
  // 商品详情页辅助
  // ==========================================================================

  /**
   * 调整数量输入
   * @param {number} delta - 变化量（+1 或 -1）
   */
  function changeQuantity(delta) {
    var input = document.getElementById('product-quantity');
    if (!input) return;
    var val = parseInt(input.value) + delta;
    if (val < 1) val = 1;
    if (val > 99) val = 99;
    input.value = val;
  }

  /**
   * 获取当前选择的数量
   * @returns {number}
   */
  function getQuantity() {
    var input = document.getElementById('product-quantity');
    return input ? parseInt(input.value) || 1 : 1;
  }

  // ==========================================================================
  // 导航栏交互
  // ==========================================================================

  /**
   * 初始化移动端导航菜单折叠
   */
  function initNavToggle() {
    var toggle = document.getElementById('nav-toggle');
    var links = document.querySelector('.nav-links');
    if (toggle && links) {
      toggle.addEventListener('click', function () {
        links.classList.toggle('open');
      });
    }
  }

  // ==========================================================================
  // HTML 转义（防 XSS）
  // ==========================================================================

  /**
   * 转义 HTML 特殊字符
   * @param {string} text
   * @returns {string}
   */
  function escapeHtml(text) {
    var div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  // ==========================================================================
  // Footer Trace ID 显示
  // ==========================================================================

  /**
   * 从 /api/health 获取 trace-id 并显示在 footer
   */
  function loadTraceId() {
    var el = document.getElementById('footer-trace-id');
    if (!el) return;

    fetch('/api/health')
      .then(function (res) { return res.json(); })
      .then(function (data) {
        if (data.traceId && data.traceId !== 'none') {
          el.textContent = 'Trace ID: ' + data.traceId;
        }
      })
      .catch(function () {
        // 静默失败，footer 不显示 trace-id
      });
  }

  // ==========================================================================
  // 初始化
  // ==========================================================================

  /**
   * 页面加载完成后执行初始化
   */
  function init() {
    // 移动端导航
    initNavToggle();

    // 更新登录状态 UI
    updateAuthUI();

    // 加载 Trace ID
    loadTraceId();

    // 如果在购物车页面，加载购物车数据
    if (document.getElementById('cart-container')) {
      loadCart();
    }
  }

  // DOM 加载完成后初始化
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  // ==========================================================================
  // 公开 API（供 HTML onclick 调用）
  // ==========================================================================
  return {
    addToCart: addToCart,
    loadCart: loadCart,
    updateCartItem: updateCartItem,
    removeFromCart: removeFromCart,
    placeOrder: placeOrder,
    switchTab: switchTab,
    handleLogin: handleLogin,
    handleRegister: handleRegister,
    handleLogout: handleLogout,
    filterByCategory: filterByCategory,
    sortProducts: sortProducts,
    changeQuantity: changeQuantity,
    getQuantity: getQuantity,
    showToast: showToast,
    isLoggedIn: isLoggedIn,
    getToken: getToken,
    getUserInfo: getUserInfo
  };

})();

// ── 全局函数绑定（方便 EJS 模板中 onclick 直接调用）────────────────────────
/* eslint-disable no-unused-vars */
function addToCart(id, qty) { UniceDemoApp.addToCart(id, qty); }
function placeOrder() { UniceDemoApp.placeOrder(); }
function switchTab(tab) { UniceDemoApp.switchTab(tab); }
function handleLogin(e) { UniceDemoApp.handleLogin(e); }
function handleRegister(e) { UniceDemoApp.handleRegister(e); }
function handleLogout() { UniceDemoApp.handleLogout(); }
function filterByCategory(cat) { UniceDemoApp.filterByCategory(cat); }
function sortProducts(sort) { UniceDemoApp.sortProducts(sort); }
function changeQuantity(d) { UniceDemoApp.changeQuantity(d); }
function getQuantity() { return UniceDemoApp.getQuantity(); }
/* eslint-enable no-unused-vars */
```

#### Step 10.10: 创建 `static/errors/403.html` — 品牌化 403 页面

- [ ] 创建文件 `static/errors/403.html`，简洁品牌化的 403 Forbidden 错误页面

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>403 - 访问被拒绝 | Unice Demo</title>
  <style>
    /* 错误页面内联样式（独立于主站 CSS，确保 S3 直接提供时也能正确渲染） */
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Noto Sans SC', sans-serif;
      background-color: #f5f7fa;
      color: #333;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .error-container {
      text-align: center;
      max-width: 480px;
    }
    .error-code {
      font-size: 6rem;
      font-weight: 700;
      color: #ea4335;
      line-height: 1;
      margin-bottom: 16px;
    }
    .error-title {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 12px;
      color: #1a1a2e;
    }
    .error-message {
      font-size: 1rem;
      color: #666;
      line-height: 1.6;
      margin-bottom: 32px;
    }
    .error-hint {
      font-size: 0.85rem;
      color: #999;
      margin-bottom: 24px;
    }
    .error-link {
      display: inline-block;
      padding: 10px 32px;
      background-color: #1a73e8;
      color: #fff;
      text-decoration: none;
      border-radius: 4px;
      font-size: 0.95rem;
      transition: background-color 0.2s;
    }
    .error-link:hover {
      background-color: #1557b0;
    }
    .error-brand {
      margin-top: 48px;
      font-size: 0.8rem;
      color: #bbb;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-code">403</div>
    <h1 class="error-title">访问被拒绝</h1>
    <p class="error-message">
      您没有权限访问此页面。这可能是由于签名 URL 已过期、WAF 安全策略拦截或地理位置限制。
    </p>
    <p class="error-hint">
      如果您认为这是一个错误，请稍后重试或联系网站管理员。
    </p>
    <a href="/" class="error-link">返回首页</a>
    <p class="error-brand">Unice Demo &mdash; CloudFront 全功能演示平台</p>
  </div>
</body>
</html>
```

#### Step 10.11: 创建 `static/errors/404.html` — 品牌化 404 页面

- [ ] 创建文件 `static/errors/404.html`，简洁品牌化的 404 Not Found 错误页面

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>404 - 页面未找到 | Unice Demo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Noto Sans SC', sans-serif;
      background-color: #f5f7fa;
      color: #333;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .error-container {
      text-align: center;
      max-width: 480px;
    }
    .error-code {
      font-size: 6rem;
      font-weight: 700;
      color: #fbbc04;
      line-height: 1;
      margin-bottom: 16px;
    }
    .error-title {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 12px;
      color: #1a1a2e;
    }
    .error-message {
      font-size: 1rem;
      color: #666;
      line-height: 1.6;
      margin-bottom: 32px;
    }
    .error-actions {
      display: flex;
      gap: 16px;
      justify-content: center;
      flex-wrap: wrap;
    }
    .error-link {
      display: inline-block;
      padding: 10px 32px;
      background-color: #1a73e8;
      color: #fff;
      text-decoration: none;
      border-radius: 4px;
      font-size: 0.95rem;
      transition: background-color 0.2s;
    }
    .error-link:hover {
      background-color: #1557b0;
    }
    .error-link-secondary {
      background-color: #fff;
      color: #333;
      border: 1px solid #ddd;
    }
    .error-link-secondary:hover {
      background-color: #f5f5f5;
    }
    .error-brand {
      margin-top: 48px;
      font-size: 0.8rem;
      color: #bbb;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-code">404</div>
    <h1 class="error-title">页面未找到</h1>
    <p class="error-message">
      您访问的页面不存在或已被移除。请检查 URL 是否正确，或返回首页浏览。
    </p>
    <div class="error-actions">
      <a href="/" class="error-link">返回首页</a>
      <a href="/products" class="error-link error-link-secondary">浏览商品</a>
    </div>
    <p class="error-brand">Unice Demo &mdash; CloudFront 全功能演示平台</p>
  </div>
</body>
</html>
```

#### Step 10.12: 创建 `static/errors/500.html` — 品牌化 500 页面

- [ ] 创建文件 `static/errors/500.html`，简洁品牌化的 500 Internal Server Error 错误页面

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>500 - 服务器错误 | Unice Demo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Noto Sans SC', sans-serif;
      background-color: #f5f7fa;
      color: #333;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .error-container {
      text-align: center;
      max-width: 480px;
    }
    .error-code {
      font-size: 6rem;
      font-weight: 700;
      color: #ea4335;
      line-height: 1;
      margin-bottom: 16px;
    }
    .error-title {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 12px;
      color: #1a1a2e;
    }
    .error-message {
      font-size: 1rem;
      color: #666;
      line-height: 1.6;
      margin-bottom: 32px;
    }
    .error-hint {
      font-size: 0.85rem;
      color: #999;
      margin-bottom: 24px;
    }
    .error-link {
      display: inline-block;
      padding: 10px 32px;
      background-color: #1a73e8;
      color: #fff;
      text-decoration: none;
      border-radius: 4px;
      font-size: 0.95rem;
      transition: background-color 0.2s;
    }
    .error-link:hover {
      background-color: #1557b0;
    }
    .error-brand {
      margin-top: 48px;
      font-size: 0.8rem;
      color: #bbb;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-code">500</div>
    <h1 class="error-title">服务器内部错误</h1>
    <p class="error-message">
      服务器遇到了意外错误，无法完成您的请求。我们的团队已收到通知，正在排查问题。
    </p>
    <p class="error-hint">
      请稍后刷新页面重试。如果问题持续，请联系网站管理员。
    </p>
    <a href="/" class="error-link">返回首页</a>
    <p class="error-brand">Unice Demo &mdash; CloudFront 全功能演示平台</p>
  </div>
</body>
</html>
```

#### Step 10.13: 创建 `static/errors/502.html` — 品牌化 502 页面

- [ ] 创建文件 `static/errors/502.html`，简洁品牌化的 502 Bad Gateway 错误页面

```html
<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>502 - 网关错误 | Unice Demo</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Noto Sans SC', sans-serif;
      background-color: #f5f7fa;
      color: #333;
      display: flex;
      align-items: center;
      justify-content: center;
      min-height: 100vh;
      padding: 24px;
    }
    .error-container {
      text-align: center;
      max-width: 480px;
    }
    .error-code {
      font-size: 6rem;
      font-weight: 700;
      color: #ff7043;
      line-height: 1;
      margin-bottom: 16px;
    }
    .error-title {
      font-size: 1.5rem;
      font-weight: 600;
      margin-bottom: 12px;
      color: #1a1a2e;
    }
    .error-message {
      font-size: 1rem;
      color: #666;
      line-height: 1.6;
      margin-bottom: 32px;
    }
    .error-hint {
      font-size: 0.85rem;
      color: #999;
      margin-bottom: 24px;
    }
    .error-link {
      display: inline-block;
      padding: 10px 32px;
      background-color: #1a73e8;
      color: #fff;
      text-decoration: none;
      border-radius: 4px;
      font-size: 0.95rem;
      transition: background-color 0.2s;
    }
    .error-link:hover {
      background-color: #1557b0;
    }
    .error-brand {
      margin-top: 48px;
      font-size: 0.8rem;
      color: #bbb;
    }
  </style>
</head>
<body>
  <div class="error-container">
    <div class="error-code">502</div>
    <h1 class="error-title">网关错误</h1>
    <p class="error-message">
      CloudFront 无法连接到源站服务器（ALB/EC2）。这通常意味着后端服务暂时不可用或正在重启中。
    </p>
    <p class="error-hint">
      请等待几秒钟后刷新页面。如果问题持续超过 5 分钟，请检查 EC2 实例和 ALB 健康检查状态。
    </p>
    <a href="/" class="error-link">返回首页</a>
    <p class="error-brand">Unice Demo &mdash; CloudFront 全功能演示平台</p>
  </div>
</body>
</html>
```

---

## 验证清单

完成所有 Step 后，按以下清单验证：

- [ ] **布局继承**：所有页面视图（index/products/product-detail/cart/login/debug）均通过 `layout('layout')` 继承公共布局
- [ ] **WAF JS SDK**：layout.ejs 的 `<head>` 中包含 `<script type="text/javascript" src="/challenge.js" defer></script>`
- [ ] **导航栏**：包含 Home / Products / Cart / Login / Debug 五个链接，当前页高亮（active class）
- [ ] **响应式**：CSS 包含 768px 和 480px 两个断点的媒体查询，导航栏在移动端折叠
- [ ] **购物车 AJAX**：main.js 中 addToCart / loadCart / updateCartItem / removeFromCart / placeOrder 均使用 fetch API
- [ ] **登录 fetch**：handleLogin 提交到 `/api/user/login`，handleRegister 提交到 `/api/user/register`
- [ ] **Token 管理**：JWT token 存储在 localStorage（key: `unice_access_token`），authFetch 自动附加 Authorization header
- [ ] **错误页面**：4 个 HTML 文件（403/404/500/502）均为自包含纯静态页面（内联 CSS），品牌风格一致
- [ ] **中文注释**：所有 CSS/JS 文件包含中文注释说明各模块用途
- [ ] **无外部依赖**：前端不引入任何第三方库（jQuery/Bootstrap/Tailwind 等），纯原生实现
