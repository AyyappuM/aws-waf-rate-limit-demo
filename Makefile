SHELL := /bin/bash
.DEFAULT_GOAL := help

AWS_REGION ?= eu-central-1
export AWS_REGION

ALB_DNS := $(shell cd 02-ecs 2>/dev/null && terraform output -raw alb_dns_name 2>/dev/null)
ALB_ARN := $(shell cd 02-ecs 2>/dev/null && terraform output -raw alb_arn 2>/dev/null)
ECS_CLUSTER := $(shell cd 02-ecs 2>/dev/null && terraform output -raw ecs_cluster_name 2>/dev/null)
ECS_SERVICE := $(shell cd 02-ecs 2>/dev/null && terraform output -raw ecs_service_name 2>/dev/null)

RATE ?= 20
WINDOW ?= 60
ARGS ?=

.PHONY: help check fmt validate deploy verify load-test tune metrics destroy clean

help: ## Show this help
	@echo "AWS WAF Rate-Limiting Demo"
	@echo ""
	@echo "AWS_REGION currently set to: $(AWS_REGION)  (override: make deploy AWS_REGION=ap-south-1)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

check: ## Verify required tools and AWS credentials are in place
	@echo "==> Checking required tools"
	@command -v terraform >/dev/null || { echo "terraform not found"; exit 1; }
	@command -v aws >/dev/null || { echo "aws cli not found"; exit 1; }
	@command -v docker >/dev/null || { echo "docker not found"; exit 1; }
	@docker buildx version >/dev/null 2>&1 || { echo "docker buildx not found"; exit 1; }
	@terraform -version | head -1
	@aws --version
	@docker --version
	@echo "==> Checking AWS credentials"
	@aws sts get-caller-identity --output table
	@echo "==> All checks passed. Using AWS_REGION=$(AWS_REGION)"

fmt: ## Format all Terraform files
	terraform fmt -recursive .

validate: ## Validate Terraform syntax in all three phases (no AWS calls)
	@for dir in 01-network 02-ecs 03-waf; do \
		echo "==> Validating $$dir"; \
		(cd $$dir && terraform init -backend=false -input=false >/dev/null && terraform validate); \
	done

deploy: check ## Deploy all phases (network -> ecs -> waf), build+push image
	./scripts/deploy.sh

verify: ## Check app/ECS/WAF health after deploy
	@if [ -z "$(ALB_DNS)" ]; then echo "No ALB DNS found — did you run 'make deploy' first?"; exit 1; fi
	@echo "==> ALB DNS: $(ALB_DNS)"
	@echo "==> /health"; curl -sf http://$(ALB_DNS)/health && echo
	@echo "==> /"; curl -sf http://$(ALB_DNS)/ && echo
	@echo "==> ECS service status"
	@aws ecs describe-services --cluster $(ECS_CLUSTER) --services $(ECS_SERVICE) \
		--query 'services[0].{running:runningCount,desired:desiredCount,status:status}' --output table
	@echo "==> WAF association"
	@aws wafv2 get-web-acl-for-resource --resource-arn $(ALB_ARN) --output table

load-test: ## Run the load-test script against the deployed ALB (pass extra flags via ARGS="-n 1000 -c 40")
	@if [ -z "$(ALB_DNS)" ]; then echo "No ALB DNS found — did you run 'make deploy' first?"; exit 1; fi
	./scripts/load-test.sh $(ALB_DNS) $(ARGS)

tune: ## Change the WAF rate limit (make tune RATE=20 WINDOW=60)
	@if [ -z "$(ALB_ARN)" ]; then echo "No ALB ARN found — did you run 'make deploy' first?"; exit 1; fi
	cd 03-waf && terraform apply -auto-approve \
		-var="aws_region=$(AWS_REGION)" \
		-var="alb_arn=$(ALB_ARN)" \
		-var="rate_limit_requests=$(RATE)" \
		-var="evaluation_window_sec=$(WINDOW)"
	@echo "==> Rate limit set to $(RATE) requests / $(WINDOW)s window"

metrics: ## Show WAF blocked-request count from CloudWatch for the last 10 minutes
	@aws cloudwatch get-metric-statistics \
		--namespace AWS/WAFV2 --metric-name BlockedRequests \
		--dimensions Name=WebACL,Value=waf-rate-demo-web-acl Name=Region,Value=$(AWS_REGION) Name=Rule,Value=rate-limit-rule \
		--start-time "$$(date -u -d '-10 minutes' +%Y-%m-%dT%H:%M:%SZ)" --end-time "$$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
		--period 60 --statistics Sum --output table

destroy: ## Tear down all phases in reverse order
	./scripts/destroy.sh

clean: ## Remove local Terraform caches (.terraform dirs) — does NOT touch state or destroy resources
	find . -name ".terraform" -type d -prune -exec rm -rf {} +
	find . -name ".terraform.lock.hcl" -delete
