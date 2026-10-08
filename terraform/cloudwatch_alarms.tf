locals {
  cloudwatch_alarm_namespace = "ContainerInsights"

  application_metric_dimensions = {
    ClusterName = "zero-downtime-eks"
    Namespace   = "zero-downtime"
    PodName     = "zero-downtime-app"
  }
}

resource "aws_cloudwatch_metric_alarm" "application_high_cpu" {
  alarm_name          = "${var.project_name}-app-high-cpu"
  alarm_description   = "Application pod CPU utilization is above 80% for 3 consecutive minutes."
  namespace           = local.cloudwatch_alarm_namespace
  metric_name         = "pod_cpu_utilization"
  dimensions          = local.application_metric_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"

  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "application_high_memory" {
  alarm_name          = "${var.project_name}-app-high-memory"
  alarm_description   = "Application pod memory utilization is above 80% for 3 consecutive minutes."
  namespace           = local.cloudwatch_alarm_namespace
  metric_name         = "pod_memory_utilization"
  dimensions          = local.application_metric_dimensions
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"

  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "application_container_restarts" {
  alarm_name        = "${var.project_name}-app-container-restarts"
  alarm_description = "Application container restart count is at least 1."
  namespace         = local.cloudwatch_alarm_namespace
  metric_name       = "pod_number_of_container_restarts"
  dimensions = {
    ClusterName = "zero-downtime-eks"
    Namespace   = "zero-downtime"
    Service     = "zero-downtime-app"
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Project = var.project_name
  }
}

resource "aws_cloudwatch_metric_alarm" "alb_target_5xx" {
  alarm_name        = "${var.project_name}-alb-target-5xx"
  alarm_description = "Application ALB target returned one or more HTTP 5xx responses."

  namespace   = "AWS/ApplicationELB"
  metric_name = "HTTPCode_Target_5XX_Count"

  dimensions = {
    LoadBalancer = "app/k8s-zerodown-zerodown-2877ae3841/303e9c043ad92bfe"
    TargetGroup  = "targetgroup/k8s-zerodown-zerodown-113eb14c89/7f3d77423693aaa8"
  }

  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 1

  comparison_operator = "GreaterThanOrEqualToThreshold"

  treat_missing_data = "notBreaching"
  alarm_actions      = [aws_sns_topic.cloudwatch_alerts.arn]

  tags = {
    Project = var.project_name
  }
}
