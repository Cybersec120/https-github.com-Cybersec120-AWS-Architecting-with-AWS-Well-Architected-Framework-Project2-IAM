# ─────────────────────────────────────────────────────────────────
# Lambda — Document Processor
# Triggered by S3 upload. Reads input. Writes output. That's it.
# ─────────────────────────────────────────────────────────────────

# Package the Lambda function code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/processor.py"
  output_path = "${path.module}/lambda/processor.zip"
}

resource "aws_lambda_function" "processor" {
  function_name    = "${var.project_name}-processor"
  description      = "Processes documents uploaded to input S3 bucket"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "processor.lambda_handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128

  environment {
    variables = {
      OUTPUT_BUCKET = aws_s3_bucket.output.id
      ENVIRONMENT   = var.environment
      LOG_LEVEL     = "INFO"
    }
  }

  # Dead letter queue — failed events go here for reprocessing
  dead_letter_config {
    target_arn = aws_sqs_queue.lambda_dlq.arn
  }

  depends_on = [
    aws_iam_role_policy_attachment.lambda_policy_attach,
    aws_cloudwatch_log_group.lambda
  ]

  tags = { Name = "${var.project_name}-processor" }
}

# Allow S3 to invoke this Lambda function
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.input.arn

  # Scope to specific account — prevents confused deputy attack
  source_account = data.aws_caller_identity.current.account_id
}

# Dead Letter Queue — catches failed Lambda invocations
resource "aws_sqs_queue" "lambda_dlq" {
  name                      = "${var.project_name}-lambda-dlq"
  message_retention_seconds = 1209600 # 14 days
  kms_master_key_id         = "alias/aws/sqs"

  tags = { Name = "${var.project_name}-dlq" }
}

# SQS policy — allow Lambda to send failed messages to DLQ
resource "aws_sqs_queue_policy" "lambda_dlq" {
  queue_url = aws_sqs_queue.lambda_dlq.id
  policy    = data.aws_iam_policy_document.dlq_policy.json
}

data "aws_iam_policy_document" "dlq_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.lambda_dlq.arn]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_lambda_function.processor.arn]
    }
  }
}
