resource "aws_sqs_queue" "transactions_dlq" {
  name                      = "${var.project_name}-${var.environment}-transactions-dlq"
  message_retention_seconds = 1209600 
}

resource "aws_sqs_queue" "transactions_ready" {
  name                       = "${var.project_name}-${var.environment}-transactions-ready"
  visibility_timeout_seconds = 60 
  message_retention_seconds  = 86400 
  
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.transactions_dlq.arn
    maxReceiveCount     = 3
  })
}

resource "aws_sns_topic" "budget_alerts" {
  name = "${var.project_name}-${var.environment}-budget-alerts"
}