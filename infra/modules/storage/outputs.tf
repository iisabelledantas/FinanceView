output "transactions_table_name" {
  description = "Nome da tabela DynamoDB de transações"
  value       = aws_dynamodb_table.transactions.name
}

output "transactions_table_arn" {
  description = "ARN da tabela DynamoDB de transações"
  value       = aws_dynamodb_table.transactions.arn
}

output "market_cache_table_name" {
  description = "Nome da tabela DynamoDB de cache de mercado"
  value       = aws_dynamodb_table.market_cache.name
}

output "market_cache_table_arn" {
  description = "ARN da tabela DynamoDB de cache de mercado"
  value       = aws_dynamodb_table.market_cache.arn
}

output "files_bucket_name" {
  description = "Nome do bucket S3 de arquivos"
  value       = aws_s3_bucket.files.bucket
}

output "files_bucket_arn" {
  description = "ARN do bucket S3 de arquivos"
  value       = aws_s3_bucket.files.arn
}

