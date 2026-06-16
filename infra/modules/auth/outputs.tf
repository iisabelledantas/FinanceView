
output "user_pool_id" {
  description = "ID do Cognito User Pool"
  value       = aws_cognito_user_pool.main.id
}

output "user_pool_arn" {
  description = "ARN do Cognito User Pool"
  value       = aws_cognito_user_pool.main.arn
}

output "client_id" {
  description = "ID do app client Flutter — usado no SDK do app"
  value       = aws_cognito_user_pool_client.flutter_app.id
}

output "user_pool_endpoint" {
  description = "Endpoint do User Pool — usado para configurar o API Gateway"
  value       = aws_cognito_user_pool.main.endpoint
}