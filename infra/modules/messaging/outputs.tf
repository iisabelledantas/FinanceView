output "transactions_queue_url" {
  value = aws_sqs_queue.transactions_ready.url
}

output "transactions_queue_arn" {
  value = aws_sqs_queue.transactions_ready.arn
}

output "transactions_dlq_arn" {
  value = aws_sqs_queue.transactions_dlq.arn
}

output "budget_alerts_topic_arn" {
  value = aws_sns_topic.budget_alerts.arn
}

