output "transactions_table_name" {
  value = module.storage.transactions_table_name
}

output "market_cache_table_name" {
  value = module.storage.market_cache_table_name
}

output "files_bucket_name" {
  value = module.storage.files_bucket_name
}

output "cognito_user_pool_id" {
  value = module.auth.user_pool_id
}

output "cognito_client_id" {
  description = "Guarde este valor — o Flutter vai precisar dele"
  value       = module.auth.client_id
}

output "market_data_function_name" {
  value = module.lambdas.market_data_function_name
}

output "ingest_function_name" {
  value = module.lambdas.ingest_function_name
}

output "transactions_queue_url" {
  value = module.messaging.transactions_queue_url
}

output "insights_function_name" {
  value = module.lambdas.insights_function_name
}

output "api_url" {
  description = "URL base da API — guarde este valor para configurar o Flutter"
  value       = module.api_gateway.api_url
}