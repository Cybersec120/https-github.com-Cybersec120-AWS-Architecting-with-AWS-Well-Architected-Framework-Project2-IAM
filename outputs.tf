output "input_bucket_name" {
  description = "S3 input bucket — EC2 uploads here"
  value       = aws_s3_bucket.input.id
}

output "output_bucket_name" {
  description = "S3 output bucket — Lambda writes processed results here"
  value       = aws_s3_bucket.output.id
}

output "ec2_instance_id" {
  description = "EC2 app server instance ID"
  value       = aws_instance.app_server.id
}

output "ec2_public_ip" {
  description = "EC2 public IP — SSH to test the upload pipeline"
  value       = aws_instance.app_server.public_ip
}

output "ec2_role_arn" {
  description = "IAM role ARN attached to EC2 via instance profile"
  value       = aws_iam_role.ec2_role.arn
}

output "lambda_role_arn" {
  description = "IAM role ARN used by the Lambda processor"
  value       = aws_iam_role.lambda_role.arn
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.processor.function_name
}

output "cloudtrail_name" {
  description = "CloudTrail trail name"
  value       = aws_cloudtrail.main.name
}

output "cloudtrail_logs_bucket" {
  description = "S3 bucket storing CloudTrail logs"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

output "dlq_url" {
  description = "SQS Dead Letter Queue URL for failed Lambda events"
  value       = aws_sqs_queue.lambda_dlq.url
}

output "test_pipeline_command" {
  description = "SSH to EC2 and run this to test the full pipeline"
  value       = "ssh ec2-user@${aws_instance.app_server.public_ip} '~/upload_document.sh'"
}
