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

variable "container_port" {
  description = "Port the Flask app listens on inside the container"
  type        = number
  default     = 8080
}

variable "vpc_id" {
  description = "VPC id from the 01-network phase"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet ids from the 01-network phase"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB security group id from the 01-network phase"
  type        = string
}

variable "ecs_tasks_security_group_id" {
  description = "ECS tasks security group id from the 01-network phase"
  type        = string
}

variable "image_tag" {
  description = "Tag of the container image to deploy from ECR"
  type        = string
  default     = "latest"
}

variable "desired_count" {
  description = "Number of ECS tasks to run"
  type        = number
  default     = 1
}

variable "fargate_cpu" {
  description = "Fargate task CPU units"
  type        = string
  default     = "256"
}

variable "fargate_memory" {
  description = "Fargate task memory (MiB)"
  type        = string
  default     = "512"
}
