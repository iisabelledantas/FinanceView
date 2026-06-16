output "market_data_function_name" {
  value = aws_lambda_function.market_data.function_name
}

output "market_data_function_arn" {
  value = aws_lambda_function.market_data.arn
}

output "ingest_function_name" {
  value = aws_lambda_function.ingest.function_name
}

output "ingest_function_arn" {
  value = aws_lambda_function.ingest.arn
}

output "insights_function_name" {
  value = aws_lambda_function.insights.function_name
}

output "insights_function_arn" {
  value = aws_lambda_function.insights.arn
}