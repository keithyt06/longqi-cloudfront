#!/bin/bash
set -euo pipefail

# ============================================================
# deploy-static.sh — S3 静态资源上传脚本
# 用法: ./scripts/deploy-static.sh [--bucket xxx] [--invalidate]
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUCKET="${BUCKET:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw s3_bucket_name)}"
DISTRIBUTION_ID="${DISTRIBUTION_ID:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw cloudfront_distribution_id)}"
REGION="${REGION:-ap-northeast-1}"
INVALIDATE="${INVALIDATE:-false}"

echo "==> S3 Bucket: ${BUCKET}"
echo "==> Region: ${REGION}"

# ----------------------------------------------------------
# 1. 上传图片（长缓存，24 小时）
# ----------------------------------------------------------
echo "==> 上传 static/images/ → s3://${BUCKET}/images/"
aws s3 sync "${PROJECT_ROOT}/static/images/" "s3://${BUCKET}/images/" \
  --region "${REGION}" \
  --cache-control "public, max-age=86400" \
  --delete

# ----------------------------------------------------------
# 2. 上传字体（长缓存，7 天）
# ----------------------------------------------------------
echo "==> 上传 static/fonts/ → s3://${BUCKET}/static/fonts/"
aws s3 sync "${PROJECT_ROOT}/static/fonts/" "s3://${BUCKET}/static/fonts/" \
  --region "${REGION}" \
  --cache-control "public, max-age=604800" \
  --delete

# ----------------------------------------------------------
# 3. 上传通用静态资源（长缓存，24 小时）
# ----------------------------------------------------------
echo "==> 上传 static/assets/ → s3://${BUCKET}/static/assets/"
aws s3 sync "${PROJECT_ROOT}/static/assets/" "s3://${BUCKET}/static/assets/" \
  --region "${REGION}" \
  --cache-control "public, max-age=86400" \
  --delete

# ----------------------------------------------------------
# 4. 上传自定义错误页面（短缓存，5 分钟）
# ----------------------------------------------------------
echo "==> 上传 static/errors/ → s3://${BUCKET}/static/errors/"
aws s3 sync "${PROJECT_ROOT}/static/errors/" "s3://${BUCKET}/static/errors/" \
  --region "${REGION}" \
  --content-type "text/html" \
  --cache-control "public, max-age=300" \
  --delete

# ----------------------------------------------------------
# 5. 上传 CSS（中等缓存，1 小时，便于开发迭代）
# ----------------------------------------------------------
echo "==> 上传 app/public/css/ → s3://${BUCKET}/static/css/"
aws s3 sync "${PROJECT_ROOT}/app/public/css/" "s3://${BUCKET}/static/css/" \
  --region "${REGION}" \
  --content-type "text/css" \
  --cache-control "public, max-age=3600" \
  --delete

# ----------------------------------------------------------
# 6. 上传 JavaScript（中等缓存，1 小时）
# ----------------------------------------------------------
echo "==> 上传 app/public/js/ → s3://${BUCKET}/static/js/"
aws s3 sync "${PROJECT_ROOT}/app/public/js/" "s3://${BUCKET}/static/js/" \
  --region "${REGION}" \
  --content-type "application/javascript" \
  --cache-control "public, max-age=3600" \
  --delete

# ----------------------------------------------------------
# 7. 可选：触发 CloudFront 缓存失效
# ----------------------------------------------------------
if [ "${INVALIDATE}" = "true" ] || [ "${1:-}" = "--invalidate" ]; then
  echo "==> 触发 CloudFront 缓存失效: /static/* /images/*"
  aws cloudfront create-invalidation \
    --distribution-id "${DISTRIBUTION_ID}" \
    --paths "/static/*" "/images/*" \
    --region "${REGION}" \
    --query 'Invalidation.Id' --output text
  echo "==> 缓存失效已提交（传播需要数分钟）"
fi

echo "==> 静态资源上传完成"
