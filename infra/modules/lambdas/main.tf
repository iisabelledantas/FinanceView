data "archive_file" "market_data" {
  type        = "zip"
  source_dir  = "${path.root}/../backend/market_data/src"
  output_path = "${path.root}/../backend/market_data/dist/market_data.zip"
}

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "market_data" {
  name               = "${var.project_name}-${var.environment}-market-data-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}


data "aws_iam_policy_document" "market_data" {

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:*"]
  }


  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem"
    ]

    resources = [
      var.market_cache_table_arn,
      "${var.market_cache_table_arn}/*",
    ]
  }
}

resource "aws_iam_policy" "market_data" {
  name   = "${var.project_name}-${var.environment}-market-data-policy"
  policy = data.aws_iam_policy_document.market_data.json
}

resource "aws_iam_role_policy_attachment" "market_data" {
  role       = aws_iam_role.market_data.name
  policy_arn = aws_iam_policy.market_data.arn
}


resource "aws_lambda_function" "market_data" {
  function_name = "${var.project_name}-${var.environment}-market-data"
  description   = "Busca SELIC, IPCA e câmbio e grava no cache DynamoDB"

  filename         = data.archive_file.market_data.output_path
  source_code_hash = data.archive_file.market_data.output_base64sha256

  runtime = "python3.12"
  handler = "handler.handler"

  role = aws_iam_role.market_data.arn

  timeout     = 30
  memory_size = 128

  environment {
    variables = {
      MARKET_CACHE_TABLE = var.market_cache_table_name
      ENVIRONMENT        = var.environment
    }
  }
}


resource "aws_cloudwatch_log_group" "market_data" {
  name              = "/aws/lambda/${aws_lambda_function.market_data.function_name}"
  retention_in_days = 7
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.project_name}-${var.environment}-scheduler-role"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume_role.json
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [aws_lambda_function.market_data.arn]
  }
}

resource "aws_iam_policy" "scheduler_invoke" {
  name   = "${var.project_name}-${var.environment}-scheduler-invoke-policy"
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_iam_role_policy_attachment" "scheduler_invoke" {
  role       = aws_iam_role.scheduler.name
  policy_arn = aws_iam_policy.scheduler_invoke.arn
}

resource "aws_scheduler_schedule" "market_data" {
  name        = "${var.project_name}-${var.environment}-market-data-cron"
  description = "Atualiza indicadores de mercado a cada 15 minutos"


  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = "rate(15 minutes)"

  target {
    arn      = aws_lambda_function.market_data.arn
    role_arn = aws_iam_role.scheduler.arn

    input = jsonencode({
      source    = "eventbridge-scheduler"
      scheduled = true
    })

    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}


data "archive_file" "ingest" {
  type        = "zip"
  source_dir  = "${path.root}/../backend/ingest/src"
  output_path = "${path.root}/../backend/ingest/dist/ingest.zip"
}

resource "aws_iam_role" "ingest" {
  name               = "${var.project_name}-${var.environment}-ingest-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "ingest" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect  = "Allow"
    actions = ["dynamodb:PutItem", "dynamodb:BatchWriteItem"]
    resources = [
      var.transactions_table_arn,
      "${var.transactions_table_arn}/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${var.files_bucket_arn}/statements/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "textract:StartDocumentTextDetection",
      "textract:GetDocumentTextDetection",
    ]
    resources = ["*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:PutObject"]
    resources = ["${var.files_bucket_arn}/statements/*"]
  }

  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [var.transactions_queue_arn]
  }

  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ingest" {
  name   = "${var.project_name}-${var.environment}-ingest-policy"
  policy = data.aws_iam_policy_document.ingest.json
}

resource "aws_iam_role_policy_attachment" "ingest" {
  role       = aws_iam_role.ingest.name
  policy_arn = aws_iam_policy.ingest.arn
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${var.project_name}-${var.environment}-ingest"
  description      = "Parse OFX/CSV, normaliza OFB, categoriza e persiste transações"
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"
  role             = aws_iam_role.ingest.arn
  timeout          = 60
  memory_size      = 256
  environment {
    variables = {
      TRANSACTIONS_TABLE             = var.transactions_table_name
      FILES_BUCKET                   = var.files_bucket_name
      TRANSACTIONS_QUEUE_URL         = var.transactions_queue_url
      MAX_PDF_OCR_REINVOKES          = "3"
      TEXTRACT_MAX_ATTEMPTS          = "25"
      TEXTRACT_POLL_INTERVAL_SECONDS = "2"
      ENVIRONMENT                    = var.environment
    }
  }
}

resource "aws_cloudwatch_log_group" "ingest" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 7
}


data "archive_file" "insights" {
  type        = "zip"
  source_dir  = "${path.root}/../backend/insights/src"
  output_path = "${path.root}/../backend/insights/dist/insights.zip"
}

resource "aws_iam_role" "insights" {
  name               = "${var.project_name}-${var.environment}-insights-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

data "aws_iam_policy_document" "insights" {
  statement {
    effect    = "Allow"
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:aws:logs:*:*:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:Query",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      var.transactions_table_arn,
      "${var.transactions_table_arn}/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["dynamodb:GetItem"]
    resources = [var.market_cache_table_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
    ]
    resources = [var.transactions_queue_arn]
  }
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [var.budget_alerts_topic_arn]
  }
}

resource "aws_iam_policy" "insights" {
  name   = "${var.project_name}-${var.environment}-insights-policy"
  policy = data.aws_iam_policy_document.insights.json
}

resource "aws_iam_role_policy_attachment" "insights" {
  role       = aws_iam_role.insights.name
  policy_arn = aws_iam_policy.insights.arn
}

resource "aws_lambda_function" "insights" {
  function_name    = "${var.project_name}-${var.environment}-insights"
  description      = "Calcula saúde financeira e verifica metas de orçamento"
  filename         = data.archive_file.insights.output_path
  source_code_hash = data.archive_file.insights.output_base64sha256
  runtime          = "python3.12"
  handler          = "handler.handler"
  role             = aws_iam_role.insights.arn
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      TRANSACTIONS_TABLE      = var.transactions_table_name
      MARKET_CACHE_TABLE      = var.market_cache_table_name
      BUDGET_ALERTS_TOPIC_ARN = var.budget_alerts_topic_arn
      ENVIRONMENT             = var.environment
    }
  }
}

resource "aws_cloudwatch_log_group" "insights" {
  name              = "/aws/lambda/${aws_lambda_function.insights.function_name}"
  retention_in_days = 7
}

resource "aws_lambda_event_source_mapping" "insights_from_sqs" {
  event_source_arn        = var.transactions_queue_arn
  function_name           = aws_lambda_function.insights.arn
  batch_size              = 1
  function_response_types = ["ReportBatchItemFailures"]
}
