# =================================================================
# IAM — The Heart of This Project
# Three principals. Each with exactly what they need. Nothing more.
# =================================================================

# ─────────────────────────────────────────────────────────────────
# EC2 IAM Role + Instance Profile
# Purpose: Allow the app server to upload files to S3
# WITHOUT storing AWS credentials on the machine
# ─────────────────────────────────────────────────────────────────

# Trust policy — only EC2 service can assume this role
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    sid     = "EC2AssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ec2_role" {
  name               = "${var.project_name}-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  description        = "EC2 instance role — least privilege S3 upload only"

  tags = { Name = "${var.project_name}-ec2-role" }
}

# EC2 permissions — can ONLY upload to input bucket
# Cannot read output, cannot delete, cannot touch any other service
data "aws_iam_policy_document" "ec2_permissions" {
  statement {
    sid    = "AllowS3Upload"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*"
    ]
  }

  # Allow EC2 to write its own logs to CloudWatch
  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/${var.project_name}/ec2:*"]
  }
}

resource "aws_iam_policy" "ec2_policy" {
  name        = "${var.project_name}-ec2-policy"
  description = "Least privilege policy for EC2 app server"
  policy      = data.aws_iam_policy_document.ec2_permissions.json
}

resource "aws_iam_role_policy_attachment" "ec2_policy_attach" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = aws_iam_policy.ec2_policy.arn
}

# Instance profile — this is what attaches the role to the EC2 instance
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.project_name}-ec2-instance-profile"
  role = aws_iam_role.ec2_role.name
}

# ─────────────────────────────────────────────────────────────────
# Lambda IAM Role
# Purpose: Read from input bucket, write to output bucket
# Trigger: S3 event — no human ever invokes this directly
# ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    sid     = "LambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  description        = "Lambda execution role — read input, write output, nothing else"

  tags = { Name = "${var.project_name}-lambda-role" }
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Read from input bucket ONLY
  statement {
    sid    = "AllowReadInput"
    effect = "Allow"
    actions = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }

  # Write to output bucket ONLY
  statement {
    sid    = "AllowWriteOutput"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:ListBucket"
    ]
    resources = [
      aws_s3_bucket.output.arn,
      "${aws_s3_bucket.output.arn}/*"
    ]
  }

  # CloudWatch Logs — Lambda needs this for its own logging
  statement {
    sid    = "AllowLambdaLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project_name}-processor:*"]
  }
}

resource "aws_iam_policy" "lambda_policy" {
  name        = "${var.project_name}-lambda-policy"
  description = "Least privilege policy for document processor Lambda"
  policy      = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attach" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = aws_iam_policy.lambda_policy.arn
}

# ─────────────────────────────────────────────────────────────────
# CloudTrail IAM Role
# Purpose: Allow CloudTrail to write logs to CloudWatch
# ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "cloudtrail_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cloudtrail_role" {
  name               = "${var.project_name}-cloudtrail-role"
  assume_role_policy = data.aws_iam_policy_document.cloudtrail_assume_role.json
  description        = "Allows CloudTrail to deliver logs to CloudWatch"
}

data "aws_iam_policy_document" "cloudtrail_cloudwatch" {
  statement {
    effect  = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["${aws_cloudwatch_log_group.cloudtrail.arn}:*"]
  }
}

resource "aws_iam_policy" "cloudtrail_policy" {
  name   = "${var.project_name}-cloudtrail-cw-policy"
  policy = data.aws_iam_policy_document.cloudtrail_cloudwatch.json
}

resource "aws_iam_role_policy_attachment" "cloudtrail_policy_attach" {
  role       = aws_iam_role.cloudtrail_role.name
  policy_arn = aws_iam_policy.cloudtrail_policy.arn
}
