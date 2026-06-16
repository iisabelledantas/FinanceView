module "storage" {
  source       = "./modules/storage"
  project_name = var.project_name
  environment  = var.environment
}

module "auth" {
  source       = "./modules/auth"
  project_name = var.project_name
  environment  = var.environment
}

module "messaging" {
  source       = "./modules/messaging"
  project_name = var.project_name
  environment  = var.environment
}

module "lambdas" {
  source       = "./modules/lambdas"
  project_name = var.project_name
  environment  = var.environment

  market_cache_table_name = module.storage.market_cache_table_name
  market_cache_table_arn  = module.storage.market_cache_table_arn
  transactions_table_name = module.storage.transactions_table_name
  transactions_table_arn  = module.storage.transactions_table_arn
  files_bucket_name       = module.storage.files_bucket_name
  files_bucket_arn        = module.storage.files_bucket_arn
  transactions_queue_url  = module.messaging.transactions_queue_url
  transactions_queue_arn  = module.messaging.transactions_queue_arn
  budget_alerts_topic_arn = module.messaging.budget_alerts_topic_arn
}

module "api_gateway" {
  source = "./modules/api_gateway"

  project_name           = var.project_name
  environment            = var.environment
  cognito_user_pool_arn  = module.auth.user_pool_arn
  ingest_function_arn    = module.lambdas.ingest_function_arn
  ingest_function_name   = module.lambdas.ingest_function_name
  insights_function_arn  = module.lambdas.insights_function_arn
  insights_function_name = module.lambdas.insights_function_name
}