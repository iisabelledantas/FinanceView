variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "market_cache_table_name" {
  description = "Nome da tabela DynamoDB de cache de mercado"
  type        = string
}

variable "market_cache_table_arn" {
  description = "ARN da tabela DynamoDB de cache de mercado — usado na policy IAM"
  type        = string
}

variable "transactions_table_name" {
  type = string
}

variable "transactions_table_arn" {
  type = string
}

variable "files_bucket_name" {
  type = string
}

variable "files_bucket_arn" {
  type = string
}

variable "transactions_queue_url" {
  type = string
}

variable "transactions_queue_arn" {
  type = string
}

variable "budget_alerts_topic_arn" {
  type = string
}