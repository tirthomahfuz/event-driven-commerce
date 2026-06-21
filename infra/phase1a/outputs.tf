output "alb_dns_name" {
  description = "Public HTTP endpoint for Phase 1a."
  value       = aws_lb.app.dns_name
}

output "github_deploy_role_arn" {
  description = "Role ARN to store as GitHub variable AWS_ROLE_TO_ASSUME."
  value       = aws_iam_role.github_deploy.arn
}

output "web_ecr_repository_url" {
  description = "ECR repository URL for the Next.js image."
  value       = aws_ecr_repository.web.repository_url
}

output "orders_ecr_repository_url" {
  description = "ECR repository URL for the FastAPI image."
  value       = aws_ecr_repository.orders.repository_url
}

output "cluster_name" {
  description = "ECS cluster name."
  value       = aws_ecs_cluster.main.name
}

output "web_service_name" {
  description = "ECS service name for the web app."
  value       = aws_ecs_service.web.name
}

output "orders_service_name" {
  description = "ECS service name for the orders API."
  value       = aws_ecs_service.orders.name
}
