# 06 - CloudFront 签名 URL：保护私有内容

> **演示平台**: `unice.keithyu.cloud` | **区域**: `ap-northeast-1` (东京)
>
> **预计时间**: 35-45 分钟 | **难度**: 中级 | **前置要求**: 已完成 01（Distribution + S3 Origin + `/premium/*` Behavior 已创建）
>
> **无额外费用**: 签名 URL 功能本身不产生额外费用

---

## 1. 功能概述

### 1.1 什么是签名 URL

CloudFront 签名 URL 是一种访问控制机制，用于限制对私有内容的访问。只有持有有效签名的 URL 才能通过 CloudFront 获取受保护的内容。

**典型应用场景**：
- 付费内容下载（视频课程、电子书、软件安装包）
- 会员专属资源（高清图片、独家报告）
- 限时下载链接（分享链接 1 小时后自动失效）
- 防盗链（防止第三方网站直接引用你的资源 URL）

### 1.2 签名机制原理（RSA 非对称加密）

```
┌───────────────────────────────────────────────────────────────────┐
│                           签名流程                                 │
│                                                                   │
│   ① 生成 RSA 2048 密钥对                                          │
│      ├─ 私钥（Private Key）→ 保存在 EC2 应用服务器上                 │
│      └─ 公钥（Public Key） → 注册到 CloudFront                     │
│                                                                   │
│   ② 用户请求签名 URL                                               │
│      用户 → /api/user/signed-url → EC2 Express                    │
│              └─ Express 用私钥签名 URL + 过期时间                   │
│              └─ 返回签名 URL 给用户                                 │
│                                                                   │
│   ③ CloudFront 验证签名                                            │
│      用户用签名 URL 访问 /premium/* →                               │
│        CloudFront 用注册的公钥验证签名                               │
│        ├─ 签名有效 + 未过期 → 放行 → 返回 S3 内容                   │
│        └─ 签名无效 / 已过期 → 403 Forbidden                        │
└───────────────────────────────────────────────────────────────────┘
```

### 1.3 签名 URL vs 签名 Cookie

| 维度 | 签名 URL | 签名 Cookie |
|------|---------|------------|
| 保护粒度 | 单个文件 | 多个文件（路径模式匹配） |
| URL 是否变化 | 是（URL 包含签名参数） | 否（原始 URL 不变） |
| 适用场景 | 单文件下载、分享链接 | HLS 视频流（多 .ts 分片）、整个目录 |
| 实现复杂度 | 较低 | 较高 |

**本平台使用签名 URL**，保护 `/premium/*` 路径下的模拟会员内容。

---

## 2. 前提条件

| 资源 | 说明 | 验证命令 |
|------|------|---------|
| S3 桶 | 存放 `/premium/*` 内容 | `aws s3 ls s3://unice-static-keithyu-tokyo/premium/ --region ap-northeast-1` |
| CloudFront Distribution | `/premium/*` Behavior 已配置指向 S3 Origin | 打开 Distribution → Behaviors → 确认 `/premium/*` 存在 |
| Node.js 环境 | EC2 上已安装 Node.js 18+ | `node -v` |

```bash
# 设置环境变量
DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Aliases.Items[0]=='unice.keithyu.cloud'].Id" \
  --output text)

echo "Distribution ID: $DIST_ID"
```

---

## 3. 操作步骤

### 步骤 1: 生成 RSA 2048 密钥对

使用 OpenSSL 生成 RSA 非对称密钥对。私钥用于签名，公钥注册到 CloudFront 用于验证。

- [ ] 在本地或 EC2 上执行以下命令：

```bash
# 创建密钥存放目录
mkdir -p /tmp/cloudfront-keys

# 生成 RSA 2048 位私钥（PKCS#8 格式，CloudFront 要求）
openssl genrsa -out /tmp/cloudfront-keys/private_key.pem 2048

# 从私钥导出公钥
openssl rsa -pubout \
  -in /tmp/cloudfront-keys/private_key.pem \
  -out /tmp/cloudfront-keys/public_key.pem

# 验证密钥对
echo "=== 私钥信息 ==="
openssl rsa -in /tmp/cloudfront-keys/private_key.pem -text -noout | head -5

echo ""
echo "=== 公钥信息 ==="
openssl rsa -pubin -in /tmp/cloudfront-keys/public_key.pem -text -noout | head -5

echo ""
echo "=== 公钥内容（注册到 CloudFront 时使用）==="
cat /tmp/cloudfront-keys/public_key.pem
```

> **安全注意**：
> - **私钥**（`private_key.pem`）必须安全保存，仅存放在 EC2 应用服务器上。泄露私钥意味着任何人都可以伪造签名 URL
> - **公钥**（`public_key.pem`）注册到 CloudFront，可以公开
> - 生产环境建议将私钥存储在 AWS Secrets Manager 或 SSM Parameter Store 中

---

### 步骤 2: 在 CloudFront Console 创建 Public Key

- [ ] 打开 **CloudFront Console** → 左侧菜单 **Key management** → **Public keys**
- [ ] 点击 **Create public key**

| 参数 | 值 |
|------|-----|
| Name | `unice-demo-signing-key` |
| Comment | `RSA 2048 public key for signed URL` |
| Key value | 粘贴 `public_key.pem` 的完整内容（包括 BEGIN/END 行） |

公钥内容格式示例：

```
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...
（Base64 编码内容）
...
-----END PUBLIC KEY-----
```

- [ ] 点击 **Create public key**
- [ ] **记录 Public Key ID**（格式如 `K1XXXXXXXXXX`），后续步骤需要使用

```bash
# CLI 创建 Public Key
PUBLIC_KEY_ENCODED=$(cat /tmp/cloudfront-keys/public_key.pem)

CALLER_REF="unice-demo-$(date +%Y%m%d%H%M%S)"

aws cloudfront create-public-key \
  --public-key-config '{
    "CallerReference": "'$CALLER_REF'",
    "Name": "unice-demo-signing-key",
    "Comment": "RSA 2048 public key for signed URL",
    "EncodedKey": "'"$(cat /tmp/cloudfront-keys/public_key.pem)"'"
  }'

# 记录 Public Key ID
PUBLIC_KEY_ID=$(aws cloudfront list-public-keys \
  --query "PublicKeyList.Items[?Name=='unice-demo-signing-key'].Id" \
  --output text)

echo "Public Key ID: $PUBLIC_KEY_ID"
```

---

### 步骤 3: 创建 Key Group

Key Group 是一组 Public Key 的集合。CloudFront 使用 Key Group（而非单个 Key）来验证签名，支持密钥轮换——添加新密钥到 Group 后可以安全地停用旧密钥。

- [ ] 打开 **CloudFront Console** → **Key management** → **Key groups**
- [ ] 点击 **Create key group**

| 参数 | 值 |
|------|-----|
| Name | `unice-demo-key-group` |
| Comment | `Key group for unice demo signed URLs` |
| Public keys | 选择 `unice-demo-signing-key`（勾选步骤 2 创建的公钥） |

- [ ] 点击 **Create key group**

```bash
# CLI 创建 Key Group
aws cloudfront create-key-group \
  --key-group-config '{
    "Name": "unice-demo-key-group",
    "Comment": "Key group for unice demo signed URLs",
    "Items": ["'$PUBLIC_KEY_ID'"]
  }'

# 记录 Key Group ID
KEY_GROUP_ID=$(aws cloudfront list-key-groups \
  --query "KeyGroupList.Items[?KeyGroup.KeyGroupConfig.Name=='unice-demo-key-group'].KeyGroup.Id" \
  --output text)

echo "Key Group ID: $KEY_GROUP_ID"
```

---

### 步骤 4: 配置 /premium/* Behavior 的 Trusted Key Group

将 Key Group 关联到 `/premium/*` Behavior，启用签名验证。

- [ ] 打开 **CloudFront Console** → 选择 Distribution → **Behaviors** 标签
- [ ] 找到 `/premium/*` Behavior → 点击 **Edit**
- [ ] 在 **Restrict viewer access** 部分：

| 参数 | 值 |
|------|-----|
| Restrict viewer access | **Yes** |
| Trusted authorization type | **Trusted key groups (recommended)** |
| Trusted key groups | 选择 `unice-demo-key-group` |

> **Trusted key groups vs Trusted signer**：
> - **Trusted key groups（推荐）**：使用 Key Group 管理签名密钥，支持密钥轮换，IAM 权限控制
> - **Trusted signer（旧版）**：使用 AWS 账号的 CloudFront Key Pair（需要 root 账号操作），AWS 已不推荐

- [ ] 点击 **Save changes**
- [ ] 等待 Distribution 状态变为 **Deployed**

```bash
# CLI 更新 /premium/* Behavior（需要获取当前配置后修改）
# 建议通过 Console 操作，避免 CLI 配置复杂的 JSON 编辑

# 验证 Behavior 配置
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.CacheBehaviors.Items[?PathPattern=='/premium/*'].TrustedKeyGroups" \
  --output json | jq .
```

---

### 步骤 5: 上传测试内容到 /premium/*

- [ ] 上传模拟的会员内容到 S3：

```bash
# 创建测试的会员内容
cat > /tmp/premium-content.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>Premium Content</title></head>
<body>
  <h1>会员专属内容</h1>
  <p>恭喜！您正在查看通过签名 URL 保护的私有内容。</p>
  <p>此页面仅对持有有效签名 URL 的用户可见。</p>
</body>
</html>
EOF

# 上传到 S3
aws s3 cp /tmp/premium-content.html \
  s3://unice-static-keithyu-tokyo/premium/exclusive-report.html \
  --content-type "text/html" \
  --region ap-northeast-1

# 确认上传成功
aws s3 ls s3://unice-static-keithyu-tokyo/premium/ --region ap-northeast-1
```

---

### 步骤 6: Node.js 生成签名 URL

使用 AWS SDK 的 `@aws-sdk/cloudfront-signer` 包生成签名 URL。

#### 6.1 安装依赖

```bash
# 在 Express 应用目录下
cd /root/keith-space/2026-project/longqi-cloudfront/app
npm install @aws-sdk/cloudfront-signer
```

#### 6.2 签名 URL 生成代码

以下是完整的签名 URL 生成示例（可集成到 Express 路由中）：

```javascript
// signed-url-generator.js
// 用于生成 CloudFront 签名 URL 的工具模块

const { getSignedUrl } = require('@aws-sdk/cloudfront-signer');
const fs = require('fs');
const path = require('path');

// 配置
const CLOUDFRONT_DOMAIN = 'https://unice.keithyu.cloud';
const KEY_PAIR_ID = 'K1XXXXXXXXXX';  // 替换为步骤 2 记录的 Public Key ID
const PRIVATE_KEY_PATH = path.join(__dirname, 'keys', 'private_key.pem');

/**
 * 生成 CloudFront 签名 URL
 * @param {string} resourcePath - 资源路径，如 '/premium/exclusive-report.html'
 * @param {number} expiresInSeconds - 过期时间（秒），默认 3600（1 小时）
 * @returns {string} 签名 URL
 */
function generateSignedUrl(resourcePath, expiresInSeconds = 3600) {
  // 读取私钥
  const privateKey = fs.readFileSync(PRIVATE_KEY_PATH, 'utf8');

  // 计算过期时间
  const expiresAt = new Date(Date.now() + expiresInSeconds * 1000);

  // 生成签名 URL
  const signedUrl = getSignedUrl({
    url: `${CLOUDFRONT_DOMAIN}${resourcePath}`,
    keyPairId: KEY_PAIR_ID,
    privateKey: privateKey,
    dateLessThan: expiresAt.toISOString(),
  });

  return signedUrl;
}

// 示例：直接运行时生成测试签名 URL
if (require.main === module) {
  const url = generateSignedUrl('/premium/exclusive-report.html', 3600);
  console.log('签名 URL（有效期 1 小时）：');
  console.log(url);
  console.log('');
  console.log('使用 curl 测试：');
  console.log(`curl -s -o /dev/null -w "HTTP Status: %{http_code}\\n" "${url}"`);
}

module.exports = { generateSignedUrl };
```

#### 6.3 集成到 Express 路由

```javascript
// routes/user.js 中添加签名 URL 端点
const { generateSignedUrl } = require('../signed-url-generator');

// GET /api/user/signed-url — 生成签名 URL（需 JWT 认证）
router.get('/signed-url', cognitoAuth, (req, res) => {
  const resourcePath = req.query.path || '/premium/exclusive-report.html';
  const expiresIn = parseInt(req.query.expires) || 3600;  // 默认 1 小时

  try {
    const signedUrl = generateSignedUrl(resourcePath, expiresIn);

    res.json({
      success: true,
      signedUrl: signedUrl,
      expiresIn: expiresIn,
      resource: resourcePath,
      generatedAt: new Date().toISOString(),
    });
  } catch (error) {
    console.error('签名 URL 生成失败:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate signed URL',
    });
  }
});
```

#### 6.4 生成测试签名 URL

```bash
# 方式一：运行 Node.js 脚本直接生成
node /root/keith-space/2026-project/longqi-cloudfront/app/signed-url-generator.js

# 方式二：通过 Express API 生成（需要 JWT 认证）
# 先登录获取 token
TOKEN=$(curl -s -X POST https://unice.keithyu.cloud/api/user/login \
  -H "Content-Type: application/json" \
  -d '{"username":"testuser","password":"TestPass123!"}' | jq -r '.token')

# 生成签名 URL
curl -s -H "Authorization: Bearer $TOKEN" \
  "https://unice.keithyu.cloud/api/user/signed-url?path=/premium/exclusive-report.html&expires=3600" | jq .
```

---

### 步骤 7: 验证签名 URL

#### 7.1 无签名访问 — 应返回 403

```bash
# 直接访问 /premium/* 路径（无签名）— 应返回 403
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" \
  "https://unice.keithyu.cloud/premium/exclusive-report.html"

# 预期：HTTP Status: 403
```

```bash
# 查看 403 响应内容
curl -s "https://unice.keithyu.cloud/premium/exclusive-report.html"

# 预期：CloudFront 返回 Missing Key error 或自定义 403 错误页面
# <?xml version="1.0" encoding="UTF-8"?>
# <Error><Code>MissingKey</Code><Message>Missing Key-Pair-Id query parameter or cookie value</Message></Error>
```

#### 7.2 使用签名 URL 访问 — 应返回 200

```bash
# 生成签名 URL（使用步骤 6 的 Node.js 脚本获取）
SIGNED_URL="<粘贴步骤 6.4 生成的签名 URL>"

# 使用签名 URL 访问 — 应返回 200
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" "$SIGNED_URL"

# 预期：HTTP Status: 200
```

```bash
# 查看签名 URL 的内容
curl -s "$SIGNED_URL"

# 预期：返回 premium-content.html 的内容
# <h1>会员专属内容</h1>
# <p>恭喜！您正在查看通过签名 URL 保护的私有内容。</p>
```

#### 7.3 使用过期的签名 URL — 应返回 403

```bash
# 生成一个极短有效期（5 秒）的签名 URL
node -e "
const { getSignedUrl } = require('@aws-sdk/cloudfront-signer');
const fs = require('fs');
const privateKey = fs.readFileSync('/tmp/cloudfront-keys/private_key.pem', 'utf8');
const url = getSignedUrl({
  url: 'https://unice.keithyu.cloud/premium/exclusive-report.html',
  keyPairId: 'K1XXXXXXXXXX',  // 替换为实际 Public Key ID
  privateKey: privateKey,
  dateLessThan: new Date(Date.now() + 5000).toISOString(),
});
console.log(url);
" > /tmp/short-lived-url.txt

SHORT_URL=$(cat /tmp/short-lived-url.txt)

# 立即访问 — 应返回 200
curl -s -o /dev/null -w "Immediate: HTTP Status: %{http_code}\n" "$SHORT_URL"

# 等待 10 秒后访问 — 应返回 403
sleep 10
curl -s -o /dev/null -w "After 10s: HTTP Status: %{http_code}\n" "$SHORT_URL"

# 预期：
# Immediate: HTTP Status: 200
# After 10s: HTTP Status: 403
```

#### 7.4 篡改签名 URL — 应返回 403

```bash
# 篡改签名 URL 中的资源路径（尝试访问其他文件）
TAMPERED_URL=$(echo "$SIGNED_URL" | sed 's/exclusive-report.html/other-file.html/')

curl -s -o /dev/null -w "Tampered URL: HTTP Status: %{http_code}\n" "$TAMPERED_URL"

# 预期：HTTP Status: 403（签名校验失败，因为签名绑定了原始 URL）
```

---

## 4. 签名 URL 结构解析

签名后的 URL 包含以下查询参数：

```
https://unice.keithyu.cloud/premium/exclusive-report.html
  ?Expires=1744732800
  &Signature=BASE64_ENCODED_SIGNATURE
  &Key-Pair-Id=K1XXXXXXXXXX
```

| 参数 | 说明 |
|------|------|
| `Expires` | URL 过期的 Unix 时间戳（UTC） |
| `Signature` | 使用私钥对策略文档（包含 URL + 过期时间）的 RSA-SHA1 签名，Base64 编码 |
| `Key-Pair-Id` | Public Key ID，CloudFront 用此 ID 查找对应的公钥来验证签名 |

---

## 5. 常见问题排查

### 问题 1: 签名 URL 返回 403 — Access Denied

**排查步骤**：

```bash
# 检查 1: Public Key 是否已注册
aws cloudfront list-public-keys \
  --query "PublicKeyList.Items[].{Id:Id,Name:Name}" \
  --output table

# 检查 2: Key Group 是否包含正确的 Public Key
aws cloudfront list-key-groups \
  --query "KeyGroupList.Items[].KeyGroup.KeyGroupConfig.{Name:Name,Keys:Items}" \
  --output json | jq .

# 检查 3: /premium/* Behavior 是否关联了 Key Group
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.CacheBehaviors.Items[?PathPattern=='/premium/*'].{TrustedKeyGroups:TrustedKeyGroups,RestrictViewerAccess:ViewerProtocolPolicy}" \
  --output json | jq .
```

**常见原因**：
| 原因 | 解决方案 |
|------|---------|
| Key-Pair-Id 与注册的 Public Key ID 不匹配 | 确认代码中的 `keyPairId` 与 Console 中显示的 ID 一致 |
| 私钥与公钥不是同一对 | 重新从私钥导出公钥：`openssl rsa -pubout -in private_key.pem -out public_key.pem` |
| URL 已过期 | 检查 `Expires` 时间戳是否在当前时间之后 |
| Behavior 未启用 Restrict viewer access | 确认 `/premium/*` Behavior 的 Restrict viewer access 设为 Yes |

### 问题 2: PEM 格式错误

**现象**：创建 Public Key 时报错 `InvalidArgument: The public key is invalid`。

**原因和解决**：
- 确保公钥包含完整的 `-----BEGIN PUBLIC KEY-----` 和 `-----END PUBLIC KEY-----` 行
- 确保公钥没有额外的空行或空格
- 确保使用 PEM 格式（Base64 编码），不是 DER 格式

```bash
# 验证公钥格式
openssl rsa -pubin -in /tmp/cloudfront-keys/public_key.pem -noout
# 如果无错误输出，说明格式正确

# 如果密钥是 DER 格式，转换为 PEM
openssl rsa -pubin -inform DER -in public_key.der -outform PEM -out public_key.pem
```

### 问题 3: 签名 URL 中文件名包含特殊字符

**现象**：资源路径包含中文、空格或特殊字符时签名验证失败。

**解决方案**：
- 在签名时对 URL 进行正确的 URI 编码
- 确保签名时使用的 URL 与实际访问的 URL 完全一致（包括编码方式）

```javascript
// 对包含特殊字符的路径进行编码
const resourcePath = encodeURI('/premium/报告-2026.pdf');
const signedUrl = generateSignedUrl(resourcePath, 3600);
```

### 问题 4: 密钥轮换

**场景**：需要更换签名密钥（定期轮换或私钥泄露）。

**步骤**：
1. 生成新的 RSA 密钥对
2. 在 CloudFront 创建新的 Public Key
3. 将新 Public Key 添加到现有 Key Group（此时 Key Group 包含新旧两个 Key）
4. 更新 EC2 应用，使用新私钥签名
5. 等待所有已发放的旧签名 URL 过期
6. 从 Key Group 中移除旧 Public Key
7. 删除旧 Public Key

> **关键**：步骤 3 和 4 之间 Key Group 同时包含新旧两个 Key，确保过渡期内新旧签名 URL 都能验证通过。

---

## 6. 签名 URL 完整配置对照表

| 配置项 | 值 | 说明 |
|--------|-----|------|
| 密钥算法 | RSA 2048 | CloudFront 支持 1024/2048/4096，推荐 2048 |
| Public Key | `unice-demo-signing-key` | 注册到 CloudFront |
| Key Group | `unice-demo-key-group` | 包含 1 个 Public Key |
| 保护路径 | `/premium/*` | S3 上的会员内容 |
| 签名端点 | `/api/user/signed-url` | 需 JWT 认证才能调用 |
| URL 有效期 | 3600 秒（1 小时） | 可在请求时自定义 |
| IP 限制 | 无 | 可选：签名策略中指定允许的客户端 IP |

---

## 7. CLI 快速参考

```bash
# 列出所有 Public Keys
aws cloudfront list-public-keys \
  --query "PublicKeyList.Items[].{Id:Id,Name:Name,CreatedTime:CreatedTime}" \
  --output table

# 查看 Public Key 详情
aws cloudfront get-public-key --id $PUBLIC_KEY_ID

# 列出所有 Key Groups
aws cloudfront list-key-groups \
  --query "KeyGroupList.Items[].KeyGroup.{Id:Id,Name:KeyGroupConfig.Name,Keys:KeyGroupConfig.Items}" \
  --output table

# 查看 /premium/* Behavior 的签名配置
aws cloudfront get-distribution-config --id $DIST_ID \
  --query "DistributionConfig.CacheBehaviors.Items[?PathPattern=='/premium/*'].{Restricted:Restrict,TrustedKeyGroups:TrustedKeyGroups}" \
  --output json | jq .

# 删除 Public Key（先从 Key Group 移除）
# aws cloudfront delete-public-key --id $PUBLIC_KEY_ID --if-match $ETAG

# 删除 Key Group（先从 Behavior 移除）
# aws cloudfront delete-key-group --id $KEY_GROUP_ID --if-match $ETAG
```
