output "state_bucket" {
  description = "Put this in the backend \"s3\" block of infra/envs/*/main.tf."
  value       = aws_s3_bucket.state.bucket
}

output "ecr_repository_url" {
  description = "Image repository; GitHub variable ECR_REPOSITORY is its name."
  value       = aws_ecr_repository.app.repository_url
}

output "ci_push_role_arn" {
  description = "GitHub variable AWS_CI_PUSH_ROLE_ARN."
  value       = aws_iam_role.ci_push.arn
}

output "deploy_role_arn" {
  description = "GitHub variable AWS_DEPLOY_ROLE_ARN."
  value       = aws_iam_role.deploy.arn
}

output "readonly_role_arn" {
  description = "GitHub variable AWS_READONLY_ROLE_ARN (scheduled drift checks)."
  value       = aws_iam_role.readonly.arn
}
