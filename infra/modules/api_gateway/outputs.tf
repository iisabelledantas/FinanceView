output "api_url" {
  description = "URL base da API — o Flutter vai usar esta URL"
  value       = aws_api_gateway_stage.main.invoke_url
}

output "api_id" {
  value = aws_api_gateway_rest_api.main.id
}