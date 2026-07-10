#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "==> Using AWS region: ${AWS_REGION}"

# ---------------------------------------------------------------------------
# Phase 01: network
# ---------------------------------------------------------------------------
echo "==> [1/3] Applying 01-network"
cd "${ROOT_DIR}/01-network"
terraform init -input=false
terraform apply -auto-approve -input=false -var="aws_region=${AWS_REGION}"

VPC_ID="$(terraform output -raw vpc_id)"
PUBLIC_SUBNET_IDS="$(terraform output -json public_subnet_ids)"
ALB_SG_ID="$(terraform output -raw alb_security_group_id)"
ECS_SG_ID="$(terraform output -raw ecs_tasks_security_group_id)"

# ---------------------------------------------------------------------------
# Phase 02: ECR + ECS + ALB
# ---------------------------------------------------------------------------
echo "==> [2/3] Applying 02-ecs"
cd "${ROOT_DIR}/02-ecs"
terraform init -input=false

COMMON_VARS=(
  -var="aws_region=${AWS_REGION}"
  -var="vpc_id=${VPC_ID}"
  -var="public_subnet_ids=${PUBLIC_SUBNET_IDS}"
  -var="alb_security_group_id=${ALB_SG_ID}"
  -var="ecs_tasks_security_group_id=${ECS_SG_ID}"
)

echo "    -> Creating ECR repository first (needed before we can push an image)"
terraform apply -auto-approve -input=false -target=aws_ecr_repository.app "${COMMON_VARS[@]}"

ECR_REPO_URL="$(terraform output -raw ecr_repository_url)"

echo "    -> Building and pushing the Docker image to ${ECR_REPO_URL}"
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REPO_URL%%/*}"

docker buildx build --platform linux/amd64 \
  -t "${ECR_REPO_URL}:latest" \
  --push \
  "${ROOT_DIR}/app"

echo "    -> Applying the rest of 02-ecs (ECS cluster, service, ALB)"
terraform apply -auto-approve -input=false "${COMMON_VARS[@]}"

ALB_ARN="$(terraform output -raw alb_arn)"
ALB_DNS_NAME="$(terraform output -raw alb_dns_name)"

# ---------------------------------------------------------------------------
# Phase 03: WAF
# ---------------------------------------------------------------------------
echo "==> [3/3] Applying 03-waf"
cd "${ROOT_DIR}/03-waf"
terraform init -input=false
terraform apply -auto-approve -input=false \
  -var="aws_region=${AWS_REGION}" \
  -var="alb_arn=${ALB_ARN}"

echo ""
echo "==> Deploy complete!"
echo "    ALB DNS name: http://${ALB_DNS_NAME}"
echo ""
echo "    Try it out:"
echo "      curl http://${ALB_DNS_NAME}/"
echo ""
echo "    Note: WAF association can take up to ~1 minute to propagate."
echo ""
echo "    Once the app is reachable, feel the rate limit:"
echo "      ${SCRIPT_DIR}/load-test.sh ${ALB_DNS_NAME}"
