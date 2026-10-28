output "url" {
  description = "Public URL of the app (point your domain at alb_dns_name with a CNAME or Route 53 alias)."
  value       = "${local.https ? "https" : "http"}://${aws_lb.this.dns_name}"
}

output "alb_dns_name" {
  description = "Load balancer DNS name."
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "Load balancer hosted zone id (for a Route 53 alias record)."
  value       = aws_lb.this.zone_id
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.this.name
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.app.name
}

output "task_definition_arn" {
  description = "Task definition revision Terraform deployed; CD compares it with what ECS runs."
  value       = aws_ecs_task_definition.app.arn
}

output "image_tag" {
  description = "Image tag currently deployed (pass it back as TF_VAR_image_tag for infra-only plans)."
  value       = var.image_tag
}

output "log_group" {
  description = "CloudWatch log group with the app's stdout/stderr."
  value       = aws_cloudwatch_log_group.app.name
}

output "alarm_topic_arn" {
  description = "SNS topic that receives every alarm; subscribe more endpoints to it."
  value       = aws_sns_topic.alarms.arn
}

output "dashboard_url" {
  description = "CloudWatch dashboard."
  value       = "https://${var.aws_region}.console.aws.amazon.com/cloudwatch/home?region=${var.aws_region}#dashboards:name=${var.name}"
}
