# --- identity ----------------------------------------------------------------------------------
variable "name" {
  description = "Name of this deployment, usually <app>-<environment> (e.g. shop-api-staging). Prefixes every resource."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,27}$", var.name))
    error_message = "Use 2-28 characters: lowercase letters, digits and hyphens (AWS load balancer names are short)."
  }
}

variable "aws_region" {
  description = "Region the stack runs in (used for log configuration and console links)."
  type        = string
}

# --- the container -----------------------------------------------------------------------------
variable "container_image" {
  description = "Image repository WITHOUT a tag, e.g. 123456789012.dkr.ecr.us-east-1.amazonaws.com/shop-api."
  type        = string
}

variable "image_tag" {
  description = "Immutable image tag to run (git SHA or semver). Set by CD through TF_VAR_image_tag."
  type        = string
  validation {
    condition     = !contains(["latest", "main", "master", "stable", "dev", ""], var.image_tag)
    error_message = "Refusing a floating tag: deploy a git SHA or a semver tag."
  }
}

variable "container_port" {
  description = "Port the app listens on inside the container (also passed to the app as PORT)."
  type        = number
  default     = 8080
}

variable "health_check_path" {
  description = "Path the load balancer polls; must return 200 when the app can serve traffic."
  type        = string
  default     = "/healthz"
}

variable "cpu" {
  description = "Fargate CPU units per task (256 = 0.25 vCPU, 512, 1024, 2048, 4096)."
  type        = number
  default     = 256
}

variable "memory" {
  description = "Fargate memory per task in MiB (must be valid for the chosen cpu, e.g. 512-2048 for 256)."
  type        = number
  default     = 512
}

variable "cpu_architecture" {
  description = "X86_64, or ARM64 (about 20% cheaper; the image must be built for arm64)."
  type        = string
  default     = "X86_64"
}

variable "environment_variables" {
  description = "Plain (non-secret) environment variables for the app."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables: NAME => full ARN of an SSM SecureString parameter or Secrets Manager secret. Values never touch Terraform state."
  type        = map(string)
  default     = {}
}

# --- scaling -----------------------------------------------------------------------------------
variable "min_count" {
  description = "Minimum running tasks. Use 2 or more in production so one task can fail without downtime."
  type        = number
  default     = 2
}

variable "max_count" {
  description = "Maximum running tasks autoscaling may add (caps your bill)."
  type        = number
  default     = 6
}

variable "cpu_target_percent" {
  description = "Autoscaling keeps average CPU around this value."
  type        = number
  default     = 60
}

variable "memory_target_percent" {
  description = "Autoscaling keeps average memory around this value."
  type        = number
  default     = 75
}

variable "requests_per_target" {
  description = "Optional: also scale to keep requests per task per minute around this value (0 = off)."
  type        = number
  default     = 0
}

# --- network -----------------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "Address range of the new VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "az_count" {
  description = "Availability zones to spread over (2 or 3)."
  type        = number
  default     = 2
}

variable "private_subnets" {
  description = "Run tasks in private subnets behind a NAT gateway (recommended for production; about 35 USD/month extra). When false, tasks get public IPs but only accept traffic from the load balancer."
  type        = bool
  default     = false
}

variable "certificate_arn" {
  description = "ACM certificate ARN for HTTPS. When set, HTTP redirects to HTTPS. Leave empty for HTTP only (staging experiments)."
  type        = string
  default     = ""
}

variable "deletion_protection" {
  description = "Protect the load balancer from deletion (turn on in production)."
  type        = bool
  default     = false
}

# --- monitoring --------------------------------------------------------------------------------
variable "alarm_email" {
  description = "Email that receives alarms (AWS sends a confirmation link first). Empty = alarms go to the SNS topic only."
  type        = string
  default     = ""
}

variable "alarm_5xx_threshold" {
  description = "Alarm when more than this many 5xx responses happen in 5 minutes."
  type        = number
  default     = 10
}

variable "alarm_p95_latency_seconds" {
  description = "Alarm when 95th percentile response time is above this for 10 minutes."
  type        = number
  default     = 1
}

variable "enable_container_insights" {
  description = "ECS Container Insights: per-task metrics and the running-task alarm (small extra CloudWatch cost)."
  type        = bool
  default     = true
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps application logs."
  type        = number
  default     = 30
}
