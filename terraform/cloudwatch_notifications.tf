resource "aws_sns_topic" "cloudwatch_alerts" {
  name = "${var.project_name}-cloudwatch-alerts"

  tags = {
    Project = var.project_name
  }
}

resource "aws_sns_topic_subscription" "cloudwatch_alerts_email" {
  topic_arn = aws_sns_topic.cloudwatch_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
