#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AWS_REGION="${AWS_REGION:-us-east-1}"

echo "==> Destroying in reverse order: 03-waf -> 02-ecs -> 01-network"

# ---------------------------------------------------------------------------
# Phase 03: WAF (reads alb_arn from 02-ecs, which is still up at this point)
# ---------------------------------------------------------------------------
if [ -d "${SCRIPT_DIR}/03-waf/.terraform" ]; then
  echo "==> [1/3] Destroying 03-waf"
  ALB_ARN="$(cd "${SCRIPT_DIR}/02-ecs" && terraform output -raw alb_arn)"
  cd "${SCRIPT_DIR}/03-waf"
  terraform destroy -auto-approve -input=false \
    -var="aws_region=${AWS_REGION}" \
    -var="alb_arn=${ALB_ARN}"
else
  echo "==> [1/3] Skipping 03-waf (not initialized)"
fi

# ---------------------------------------------------------------------------
# Phase 02: ECS (reads network ids from 01-network, which is still up here)
# ---------------------------------------------------------------------------
if [ -d "${SCRIPT_DIR}/02-ecs/.terraform" ]; then
  echo "==> [2/3] Destroying 02-ecs"
  VPC_ID="$(cd "${SCRIPT_DIR}/01-network" && terraform output -raw vpc_id)"
  PUBLIC_SUBNET_IDS="$(cd "${SCRIPT_DIR}/01-network" && terraform output -json public_subnet_ids)"
  ALB_SG_ID="$(cd "${SCRIPT_DIR}/01-network" && terraform output -raw alb_security_group_id)"
  ECS_SG_ID="$(cd "${SCRIPT_DIR}/01-network" && terraform output -raw ecs_tasks_security_group_id)"

  cd "${SCRIPT_DIR}/02-ecs"
  terraform destroy -auto-approve -input=false \
    -var="aws_region=${AWS_REGION}" \
    -var="vpc_id=${VPC_ID}" \
    -var="public_subnet_ids=${PUBLIC_SUBNET_IDS}" \
    -var="alb_security_group_id=${ALB_SG_ID}" \
    -var="ecs_tasks_security_group_id=${ECS_SG_ID}"
else
  echo "==> [2/3] Skipping 02-ecs (not initialized)"
fi

# ---------------------------------------------------------------------------
# Phase 01: network
# ---------------------------------------------------------------------------
if [ -d "${SCRIPT_DIR}/01-network/.terraform" ]; then
  echo "==> [3/3] Destroying 01-network"
  cd "${SCRIPT_DIR}/01-network"
  terraform destroy -auto-approve -input=false -var="aws_region=${AWS_REGION}"
else
  echo "==> [3/3] Skipping 01-network (not initialized)"
fi

echo "==> Destroy complete."
