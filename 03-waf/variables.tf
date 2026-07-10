variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix used to tag/name all resources"
  type        = string
  default     = "waf-rate-demo"
}

variable "alb_arn" {
  description = "ARN of the ALB from the 02-ecs phase to attach the Web ACL to"
  type        = string
}

variable "rate_limit_requests" {
  description = "Max requests per IP allowed within the evaluation window before WAF starts blocking"
  type        = number
  default     = 100

  validation {
    condition     = var.rate_limit_requests >= 10
    error_message = "AWS WAFv2 rate-based rules require a limit of at least 10."
  }
}

variable "evaluation_window_sec" {
  description = "Rolling window (seconds) WAF uses to evaluate the rate-based rule. Must be one of 60, 120, 300, 600."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 120, 300, 600], var.evaluation_window_sec)
    error_message = "evaluation_window_sec must be one of: 60, 120, 300, 600."
  }
}
