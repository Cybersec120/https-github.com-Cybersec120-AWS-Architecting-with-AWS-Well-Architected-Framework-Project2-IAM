# ─────────────────────────────────────────────────────────────────
# CloudTrail — Full API Audit Logging
# Every AWS API call made by EC2, Lambda, or any principal
# is recorded. Who did what, when, from where.
# Security Pillar: "Enable traceability"
# ─────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/${var.project_name}/cloudtrail"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudtrail" "main" {
  name                          = "${var.project_name}-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  cloud_watch_logs_group_arn    = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn     = aws_iam_role.cloudtrail_role.arn
  include_global_service_events = true   # Capture IAM events (global)
  is_multi_region_trail         = false  # Single region for this demo
  enable_log_file_validation    = true   # Detect log tampering

  # Capture S3 data events — who accessed which objects
  event_selector {
    read_write_type           = "All"
    include_management_events = true

    data_resource {
      type   = "AWS::S3::Object"
      values = [
        "${aws_s3_bucket.input.arn}/",
        "${aws_s3_bucket.output.arn}/"
      ]
    }
  }

  # Capture Lambda invocations
  event_selector {
    read_write_type           = "All"
    include_management_events = false

    data_resource {
      type   = "AWS::Lambda::Function"
      values = [aws_lambda_function.processor.arn]
    }
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_cloudwatch_log_group.cloudtrail
  ]

  tags = { Name = "${var.project_name}-trail" }
}

# ─────────────────────────────────────────────────────────────────
# CloudWatch Log Groups
# ─────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-processor"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "ec2" {
  name              = "/aws/${var.project_name}/ec2"
  retention_in_days = var.log_retention_days
}

# ─────────────────────────────────────────────────────────────────
# CloudWatch Metric Filters — Detect suspicious IAM activity
# Security Pillar: "Protect data in transit and at rest"
# ─────────────────────────────────────────────────────────────────

# Alert on unauthorized API calls
resource "aws_cloudwatch_metric_filter" "unauthorized_api" {
  name           = "${var.project_name}-unauthorized-api-calls"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.errorCode = \"*UnauthorizedAccess*\") || ($.errorCode = \"AccessDenied*\") }"

  metric_transformation {
    name      = "UnauthorizedApiCalls"
    namespace = "${var.project_name}/SecurityEvents"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "unauthorized_api" {
  alarm_name          = "${var.project_name}-unauthorized-api-calls"
  alarm_description   = "SECURITY: Unauthorized API calls detected — possible credential abuse"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "UnauthorizedApiCalls"
  namespace           = "${var.project_name}/SecurityEvents"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}

# Alert on IAM policy changes
resource "aws_cloudwatch_metric_filter" "iam_changes" {
  name           = "${var.project_name}-iam-policy-changes"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name
  pattern        = "{ ($.eventName = DeleteGroupPolicy) || ($.eventName = DeleteRolePolicy) || ($.eventName = PutGroupPolicy) || ($.eventName = PutRolePolicy) || ($.eventName = AttachGroupPolicy) || ($.eventName = AttachRolePolicy) }"

  metric_transformation {
    name      = "IamPolicyChanges"
    namespace = "${var.project_name}/SecurityEvents"
    value     = "1"
  }
}

resource "aws_cloudwatch_metric_alarm" "iam_changes" {
  alarm_name          = "${var.project_name}-iam-policy-changes"
  alarm_description   = "SECURITY: IAM policy modification detected"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "IamPolicyChanges"
  namespace           = "${var.project_name}/SecurityEvents"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.security_alerts.arn]
}

# ─────────────────────────────────────────────────────────────────
# SNS — Security Alerts Topic
# ─────────────────────────────────────────────────────────────────

resource "aws_sns_topic" "security_alerts" {
  name              = "${var.project_name}-security-alerts"
  kms_master_key_id = "alias/aws/sns"
}
