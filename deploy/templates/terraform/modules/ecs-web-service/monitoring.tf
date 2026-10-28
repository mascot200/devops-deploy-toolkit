# Alarms -> SNS topic -> email (and anything else you subscribe: Slack via AWS Chatbot, PagerDuty, ...).
# Every alarm description names a runbook section in docs/RUNBOOKS.md of the deploy toolkit.

locals {
  runbook       = "https://github.com/mascot200/devops-deploy-toolkit/blob/main/docs/RUNBOOKS.md"
  alarm_actions = [aws_sns_topic.alarms.arn]
  lb_dimensions = { LoadBalancer = aws_lb.this.arn_suffix }
  tg_dimensions = { LoadBalancer = aws_lb.this.arn_suffix, TargetGroup = aws_lb_target_group.app.arn_suffix }
  ecs_dimensions = {
    ClusterName = aws_ecs_cluster.this.name
    ServiceName = aws_ecs_service.app.name
  }
}

resource "aws_sns_topic" "alarms" {
  name = "${var.name}-alarms"
}

data "aws_iam_policy_document" "alarms_topic" {
  statement {
    sid       = "CloudWatchAlarms"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
  }
  statement {
    sid       = "EcsDeploymentEvents"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  arn    = aws_sns_topic.alarms.arn
  policy = data.aws_iam_policy_document.alarms_topic.json
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alarm_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.alarms.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

# --- users see errors ------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "http_5xx" {
  alarm_name          = "${var.name}-http-5xx"
  alarm_description   = "More than ${var.alarm_5xx_threshold} server errors (5xx) in 5 minutes. Runbook: ${local.runbook}#http-5xx"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_5xx_threshold
  evaluation_periods  = 1
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions

  metric_query {
    id          = "errors"
    expression  = "FILL(app, 0) + FILL(lb, 0)"
    label       = "5xx responses"
    return_data = true
  }
  metric_query {
    id = "app"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      dimensions  = local.lb_dimensions
      period      = 300
      stat        = "Sum"
    }
  }
  metric_query {
    id = "lb"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_ELB_5XX_Count"
      dimensions  = local.lb_dimensions
      period      = 300
      stat        = "Sum"
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "latency_p95" {
  alarm_name          = "${var.name}-latency-p95"
  alarm_description   = "95% of requests should finish within ${var.alarm_p95_latency_seconds}s; they have not for 10 minutes. Runbook: ${local.runbook}#latency-p95"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = local.lb_dimensions
  extended_statistic  = "p95"
  period              = 300
  evaluation_periods  = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_p95_latency_seconds
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- the app is unhealthy ----------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "no_healthy_tasks" {
  alarm_name          = "${var.name}-no-healthy-tasks"
  alarm_description   = "CRITICAL: the load balancer has no healthy task - the site is down. Runbook: ${local.runbook}#no-healthy-tasks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "HealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 2
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "unhealthy_tasks" {
  alarm_name          = "${var.name}-unhealthy-tasks"
  alarm_description   = "At least one task has failed load balancer health checks for 5 minutes. Runbook: ${local.runbook}#unhealthy-tasks"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "UnHealthyHostCount"
  dimensions          = local.tg_dimensions
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "running_tasks_low" {
  count               = var.enable_container_insights ? 1 : 0
  alarm_name          = "${var.name}-running-tasks-low"
  alarm_description   = "Fewer than ${var.min_count} tasks running for 5 minutes (crash loop or capacity problem). Runbook: ${local.runbook}#running-tasks-low"
  namespace           = "ECS/ContainerInsights"
  metric_name         = "RunningTaskCount"
  dimensions          = local.ecs_dimensions
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  comparison_operator = "LessThanThreshold"
  threshold           = var.min_count
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- capacity: autoscaling should handle these; if they fire, max_count is too low ---------------
resource "aws_cloudwatch_metric_alarm" "cpu_high" {
  alarm_name          = "${var.name}-cpu-high"
  alarm_description   = "Average CPU above 85% for 15 minutes even with autoscaling. Runbook: ${local.runbook}#cpu-memory-high"
  namespace           = "AWS/ECS"
  metric_name         = "CPUUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

resource "aws_cloudwatch_metric_alarm" "memory_high" {
  alarm_name          = "${var.name}-memory-high"
  alarm_description   = "Average memory above 85% for 15 minutes even with autoscaling. Runbook: ${local.runbook}#cpu-memory-high"
  namespace           = "AWS/ECS"
  metric_name         = "MemoryUtilization"
  dimensions          = local.ecs_dimensions
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 85
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
}

# --- a deployment failed and ECS rolled it back -----------------------------------------------------
resource "aws_cloudwatch_event_rule" "deployment_failed" {
  name        = "${var.name}-deployment-failed"
  description = "ECS deployment circuit breaker fired (deployment failed and was rolled back)"
  event_pattern = jsonencode({
    source        = ["aws.ecs"]
    "detail-type" = ["ECS Deployment State Change"]
    resources     = [aws_ecs_service.app.id]
    detail        = { eventName = ["SERVICE_DEPLOYMENT_FAILED"] }
  })
}

resource "aws_cloudwatch_event_target" "deployment_failed" {
  rule = aws_cloudwatch_event_rule.deployment_failed.name
  arn  = aws_sns_topic.alarms.arn
}

# --- one dashboard with the numbers that matter ----------------------------------------------------
resource "aws_cloudwatch_dashboard" "this" {
  dashboard_name = var.name
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Requests and 5xx errors (per minute)"
          region = var.aws_region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", aws_lb.this.arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", "."],
            [".", "HTTPCode_ELB_5XX_Count", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Response time (seconds)"
          region = var.aws_region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", aws_lb.this.arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }],
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "CPU and memory (% of task size)"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ECS", "CPUUtilization", "ClusterName", aws_ecs_cluster.this.name, "ServiceName", aws_ecs_service.app.name],
            [".", "MemoryUtilization", ".", ".", ".", "."],
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Healthy and unhealthy tasks"
          region = var.aws_region
          stat   = "Average"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "HealthyHostCount", "TargetGroup", aws_lb_target_group.app.arn_suffix, "LoadBalancer", aws_lb.this.arn_suffix],
            [".", "UnHealthyHostCount", ".", ".", ".", "."],
          ]
        }
      },
    ]
  })
}
