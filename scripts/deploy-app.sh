#!/bin/bash
set -euo pipefail

# ============================================================
# deploy-app.sh — Express 应用部署脚本（S3 中转 + SSM 执行）
# 用法: ./scripts/deploy-app.sh [--instance-id i-xxx] [--bucket xxx]
# ============================================================

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${PROJECT_ROOT}/app"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
ARCHIVE_NAME="app-${TIMESTAMP}.tar.gz"

# 从 Terraform output 获取默认值（可通过命令行参数覆盖）
BUCKET="${BUCKET:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw s3_bucket_name)}"
INSTANCE_ID="${INSTANCE_ID:-$(cd "${PROJECT_ROOT}/terraform" && terraform output -raw ec2_instance_id)}"
REGION="${REGION:-ap-northeast-1}"

echo "==> 打包应用目录: ${APP_DIR}"
cd "${APP_DIR}"
tar czf "/tmp/${ARCHIVE_NAME}" \
  --exclude='node_modules' \
  --exclude='.env' \
  --exclude='*.log' \
  .

echo "==> 上传到 S3: s3://${BUCKET}/deploy/${ARCHIVE_NAME}"
aws s3 cp "/tmp/${ARCHIVE_NAME}" "s3://${BUCKET}/deploy/${ARCHIVE_NAME}" --region "${REGION}"

echo "==> 通过 SSM 在 EC2 上执行部署"
COMMAND_ID=$(aws ssm send-command \
  --instance-ids "${INSTANCE_ID}" \
  --document-name "AWS-RunShellScript" \
  --parameters "commands=[
    'cd /home/ec2-user',
    'aws s3 cp s3://${BUCKET}/deploy/${ARCHIVE_NAME} /tmp/${ARCHIVE_NAME}',
    'rm -rf /home/ec2-user/app.bak && mv /home/ec2-user/app /home/ec2-user/app.bak || true',
    'mkdir -p /home/ec2-user/app && tar xzf /tmp/${ARCHIVE_NAME} -C /home/ec2-user/app',
    'cd /home/ec2-user/app && npm install --production',
    'pm2 restart all',
    'pm2 save'
  ]" \
  --region "${REGION}" \
  --query 'Command.CommandId' --output text)

echo "==> SSM Command ID: ${COMMAND_ID}"
echo "==> 等待执行完成..."
aws ssm wait command-executed \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" 2>/dev/null || true

# 查看执行结果
aws ssm get-command-invocation \
  --command-id "${COMMAND_ID}" \
  --instance-id "${INSTANCE_ID}" \
  --region "${REGION}" \
  --query '{Status:Status, Output:StandardOutputContent, Error:StandardErrorContent}'

echo "==> 部署完成"
