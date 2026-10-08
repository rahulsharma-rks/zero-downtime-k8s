locals {
  container_insights_log_groups = {
    application = 14
    dataplane   = 14
    host        = 14
    performance = 14
  }
}

resource "aws_cloudwatch_log_group" "container_insights" {
  for_each = local.container_insights_log_groups

  name              = "/aws/containerinsights/${var.cluster_name}/${each.key}"
  retention_in_days = each.value

  tags = {
    Project = var.project_name
  }
}
