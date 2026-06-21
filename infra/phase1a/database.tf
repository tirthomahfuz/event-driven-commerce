resource "aws_db_subnet_group" "orders" {
  name       = "${local.name_prefix}-orders"
  subnet_ids = values(aws_subnet.public)[*].id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-orders-db-subnet-group"
  })
}

resource "aws_db_instance" "orders" {
  identifier = "${local.name_prefix}-orders"

  allocated_storage           = 20
  db_name                     = "orders"
  engine                      = "postgres"
  instance_class              = "db.t4g.micro"
  username                    = "orders_app"
  manage_master_user_password = true

  db_subnet_group_name   = aws_db_subnet_group.orders.name
  vpc_security_group_ids = [aws_security_group.database.id]
  publicly_accessible    = false

  backup_retention_period = 1
  deletion_protection     = false
  skip_final_snapshot     = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-orders-db"
  })
}
