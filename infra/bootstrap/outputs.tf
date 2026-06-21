output "state_bucket_name" {
  description = "S3 bucket name to use in the Phase 1a backend config."
  value       = aws_s3_bucket.terraform_state.bucket
}

output "lock_table_name" {
  description = "DynamoDB table name to use in the Phase 1a backend config."
  value       = aws_dynamodb_table.terraform_locks.name
}
