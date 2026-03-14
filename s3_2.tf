# ─────────────────────────────────────────────────────────────────
# S3 — Input Bucket
# EC2 uploads documents here. Lambda reads from here.
# No public access. Encrypted. Versioned.
# ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "input" {
  bucket = "${var.project_name}-input-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "input" {
  bucket                  = aws_s3_bucket.input.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "input" {
  bucket = aws_s3_bucket.input.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "input" {
  bucket = aws_s3_bucket.input.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Bucket policy — ONLY the EC2 role can PutObject, ONLY Lambda role can GetObject
resource "aws_s3_bucket_policy" "input" {
  bucket = aws_s3_bucket.input.id
  policy = data.aws_iam_policy_document.input_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.input]
}

data "aws_iam_policy_document" "input_bucket_policy" {
  # EC2 can upload files
  statement {
    sid    = "AllowEC2Upload"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ec2_role.arn]
    }
    actions   = ["s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*"
    ]
  }

  # Lambda can read files — nothing else
  statement {
    sid    = "AllowLambdaRead"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda_role.arn]
    }
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.input.arn}/*"]
  }

  # Deny everyone else — belt and suspenders
  statement {
    sid    = "DenyAllOther"
    effect = "Deny"
    principals { type = "*" identifiers = ["*"] }
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.input.arn,
      "${aws_s3_bucket.input.arn}/*"
    ]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values = [
        aws_iam_role.ec2_role.arn,
        aws_iam_role.lambda_role.arn,
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
      ]
    }
  }
}

# S3 event notification — trigger Lambda when a file is uploaded
resource "aws_s3_bucket_notification" "input_trigger" {
  bucket = aws_s3_bucket.input.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.processor.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
    filter_suffix       = ".txt"
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

# ─────────────────────────────────────────────────────────────────
# S3 — Output Bucket
# Lambda writes processed results here. EC2 cannot touch this.
# ─────────────────────────────────────────────────────────────────

resource "aws_s3_bucket" "output" {
  bucket = "${var.project_name}-output-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "output" {
  bucket                  = aws_s3_bucket.output.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "output" {
  bucket = aws_s3_bucket.output.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "output" {
  bucket = aws_s3_bucket.output.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Output bucket policy — ONLY Lambda can write here
resource "aws_s3_bucket_policy" "output" {
  bucket = aws_s3_bucket.output.id
  policy = data.aws_iam_policy_document.output_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.output]
}

data "aws_iam_policy_document" "output_bucket_policy" {
  statement {
    sid    = "AllowLambdaWrite"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.lambda_role.arn]
    }
    actions   = ["s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.output.arn,
      "${aws_s3_bucket.output.arn}/*"
    ]
  }

  # EC2 explicitly CANNOT write to output — least privilege enforced
  statement {
    sid    = "DenyEC2Access"
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.ec2_role.arn]
    }
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.output.arn,
      "${aws_s3_bucket.output.arn}/*"
    ]
  }
}

# CloudTrail logging bucket
resource "aws_s3_bucket" "cloudtrail_logs" {
  bucket = "${var.project_name}-cloudtrail-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket                  = aws_s3_bucket.cloudtrail_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    id     = "expire-old-trails"
    status = "Enabled"
    expiration { days = var.log_retention_days }
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  policy = data.aws_iam_policy_document.cloudtrail_bucket_policy.json
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]
}

data "aws_iam_policy_document" "cloudtrail_bucket_policy" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.cloudtrail_logs.arn]
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
  }
}

data "aws_caller_identity" "current" {}
