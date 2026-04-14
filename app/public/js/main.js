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
   * 提交订单 — 先获取购物车内容，再 POST 到订单 API
   */
  function placeOrder() {
    var btn = document.getElementById('btn-place-order');
    if (btn) btn.disabled = true;

    // 先获取购物车内容
    authFetch('/api/cart')
    .then(function (res) { return res.json(); })
    .then(function (cartData) {
      var items = cartData.items || [];
      if (items.length === 0) {
        showToast('购物车为空，无法下单', 'error');
        if (btn) btn.disabled = false;
        return Promise.reject('empty_cart');
      }

      // 将购物车商品转换为订单项格式
      var orderItems = items.map(function (item) {
        return {
          productId: item.productId,
          name: item.name,
          price: item.price,
          quantity: item.quantity
        };
      });

      // 提交订单
      return authFetch('/api/orders', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ items: orderItems })
      });
    })
    .then(function (res) {
      if (!res) return;
      return res.json();
    })
    .then(function (data) {
      if (!data) return;
      if (btn) btn.disabled = false;
      if (data.error) {
        showToast(data.error, 'error');
        return;
      }
      showToast('订单提交成功！订单号: ' + (data.order ? data.order.id : '-'), 'success', 5000);
      // 清空购物车并刷新
      authFetch('/api/cart', { method: 'DELETE' }).then(function () { loadCart(); });
    })
    .catch(function (err) {
      if (btn) btn.disabled = false;
      if (err === 'empty_cart') return;
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

      // 保存 token 和用户信息（后端返回 data.tokens.accessToken）
      if (data.tokens && data.tokens.accessToken) {
        setToken(data.tokens.accessToken);
      }
      if (data.user) {
        // 将顶层 traceId 合并到 user 对象（后端 traceId 在顶层，不在 user 内）
        var userWithTrace = data.user;
        userWithTrace.traceId = data.traceId || '';
        setUserInfo(userWithTrace);
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
