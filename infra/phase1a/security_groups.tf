resource "aws_security_group" "alb" {
  name        = "${local.name_prefix}-alb"
  description = "Allow public HTTP traffic to the application load balancer."
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from the internet for Phase 1a."
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow ALB to reach ECS targets."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-alb-sg"
  })
}

resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-web"
  description = "Allow ALB traffic to the Next.js task."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Next.js from ALB."
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow public-subnet task egress for image pulls, logs, and package calls."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web-sg"
  })
}

resource "aws_security_group" "orders" {
  name        = "${local.name_prefix}-orders"
  description = "Allow ALB traffic to the FastAPI task."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "FastAPI from ALB."
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Allow public-subnet task egress for AWS APIs and Postgres."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-orders-sg"
  })
}

resource "aws_security_group" "database" {
  name        = "${local.name_prefix}-db"
  description = "Allow Postgres only from the FastAPI task security group."
  vpc_id      = aws_vpc.main.id

  ingress {
    description     = "Postgres from FastAPI tasks and migration tasks."
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.orders.id]
  }

  egress {
    description = "Allow database responses."
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-sg"
  })
}
