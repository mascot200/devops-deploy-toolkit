variable "aws_region" {
  description = "AWS region for everything, e.g. us-east-1 or eu-west-1."
  type        = string
}

variable "app_name" {
  description = "Short lowercase name of the app; prefixes every resource (e.g. shop-api)."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,19}$", var.app_name))
    error_message = "Use 2-20 characters: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "github_repository" {
  description = "The GitHub repository allowed to deploy, as owner/name (e.g. acme/shop-api)."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Use the form owner/name."
  }
}

variable "github_branch" {
  description = "The branch whose workflows may push images."
  type        = string
  default     = "main"
}

variable "github_environments" {
  description = "GitHub environments whose jobs may assume the deploy role."
  type        = list(string)
  default     = ["staging", "production"]
}

variable "create_github_oidc_provider" {
  description = "Set to false if this AWS account already has the token.actions.githubusercontent.com OIDC provider."
  type        = bool
  default     = true
}

variable "ecr_keep_images" {
  description = "How many images to keep in ECR (older ones are deleted; keep enough to roll back)."
  type        = number
  default     = 50
}
