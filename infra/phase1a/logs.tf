resource "aws_cloudwatch_log_group" "web" {
  name              = "/ecs/${local.name_prefix}/web"
  retention_in_days = 14

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "orders" {
  name              = "/ecs/${local.name_prefix}/orders"
  retention_in_days = 14

  tags = local.common_tags
}
