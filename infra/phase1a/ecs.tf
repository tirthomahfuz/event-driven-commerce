resource "aws_ecs_cluster" "main" {
  name = local.name_prefix

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "web" {
  family                   = "${local.name_prefix}-web"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.web_cpu
  memory                   = var.web_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.web_task.arn

  container_definitions = jsonencode([
    {
      name      = "web"
      image     = "${aws_ecr_repository.web.repository_url}:bootstrap"
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "NODE_ENV"
          value = "production"
        },
        {
          name  = "PORT"
          value = "3000"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.web.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "web"
          mode                  = "blocking"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_task_definition" "orders" {
  family                   = "${local.name_prefix}-orders"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.orders_cpu
  memory                   = var.orders_memory
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.orders_task.arn

  container_definitions = jsonencode([
    {
      name      = "orders"
      image     = "${aws_ecr_repository.orders.repository_url}:bootstrap"
      essential = true
      portMappings = [
        {
          containerPort = 8000
          hostPort      = 8000
          protocol      = "tcp"
        }
      ]
      environment = [
        {
          name  = "DB_HOST"
          value = aws_db_instance.orders.address
        },
        {
          name  = "DB_PORT"
          value = tostring(aws_db_instance.orders.port)
        },
        {
          name  = "DB_NAME"
          value = aws_db_instance.orders.db_name
        },
        {
          name  = "DB_USERNAME"
          value = aws_db_instance.orders.username
        },
        {
          name  = "LOG_LEVEL"
          value = "INFO"
        }
      ]
      secrets = [
        {
          name      = "DB_PASSWORD"
          valueFrom = "${aws_db_instance.orders.master_user_secret[0].secret_arn}:password::"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.orders.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "orders"
          mode                  = "blocking"
        }
      }
    }
  ])

  tags = local.common_tags
}

resource "aws_ecs_service" "web" {
  name            = "${local.name_prefix}-web"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.web.arn
  desired_count   = 0
  launch_type     = "FARGATE"
  depends_on      = [aws_lb_listener.http]

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  load_balancer {
    target_group_arn = aws_lb_target_group.web.arn
    container_name   = "web"
    container_port   = 3000
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.web.id]
    subnets          = values(aws_subnet.public)[*].id
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = local.common_tags
}

resource "aws_ecs_service" "orders" {
  name            = "${local.name_prefix}-orders"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.orders.arn
  desired_count   = 0
  launch_type     = "FARGATE"
  depends_on      = [aws_lb_listener.http]

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  deployment_maximum_percent         = 200
  deployment_minimum_healthy_percent = 100
  health_check_grace_period_seconds  = 60

  load_balancer {
    target_group_arn = aws_lb_target_group.orders.arn
    container_name   = "orders"
    container_port   = 8000
  }

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.orders.id]
    subnets          = values(aws_subnet.public)[*].id
  }

  lifecycle {
    ignore_changes = [desired_count, task_definition]
  }

  tags = local.common_tags
}
