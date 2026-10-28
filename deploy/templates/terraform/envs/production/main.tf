# Root module for the production environment. Copy deploy/templates/terraform to infra/ in your repo, edit
# the CHANGE_ME values, then use the deploy-terraform-aws skill:
#   ENVIRONMENT=production TF_VAR_image_tag=<git sha> bash deploy/scripts/terraform.sh plan
# (with TF_DIR=infra/envs/production in deploy/targets.production.env). CD sets TF_VAR_image_tag for you.

terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }
  backend "s3" {
    bucket       = "CHANGE_ME-tfstate-123456789012" # output state_bucket of infra/bootstrap
    key          = "CHANGE_ME/production/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

variable "image_tag" {
  description = "Image tag to run: a git SHA or semver. CD sets it via TF_VAR_image_tag."
  type        = string
}

locals {
  app_name    = "my-app" # CHANGE_ME: same app_name as in infra/bootstrap (the ECR repository name)
  environment = "production"
  aws_region  = "us-east-1"
}

provider "aws" {
  region = local.aws_region
  default_tags {
    tags = {
      Project     = local.app_name
      Environment = local.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_ecr_repository" "app" {
  name = local.app_name
}

module "app" {
  source = "../../modules/ecs-web-service"

  name            = "${local.app_name}-${local.environment}"
  aws_region      = local.aws_region
  container_image = data.aws_ecr_repository.app.repository_url
  image_tag       = var.image_tag
  container_port  = 8080
  alarm_email     = "CHANGE_ME@example.com"

  # production: at least 2 tasks in 2 zones, private subnets, HTTPS only, protected load balancer
  cpu                 = 512
  memory              = 1024
  min_count           = 2
  max_count           = 10
  private_subnets     = true
  deletion_protection = true
  certificate_arn     = "arn:aws:acm:us-east-1:123456789012:certificate/CHANGE_ME" # ACM certificate for your domain

  environment_variables = {
    APP_ENV = local.environment
  }
  # secrets = {
  #   DATABASE_URL = "arn:aws:ssm:us-east-1:123456789012:parameter/CHANGE_ME/production/DATABASE_URL"
  # }
}

output "url" { value = module.app.url }
output "alb_dns_name" { value = module.app.alb_dns_name }
output "cluster_name" { value = module.app.cluster_name }
output "service_name" { value = module.app.service_name }
output "task_definition_arn" { value = module.app.task_definition_arn }
output "image_tag" { value = module.app.image_tag }
output "log_group" { value = module.app.log_group }
output "dashboard_url" { value = module.app.dashboard_url }
