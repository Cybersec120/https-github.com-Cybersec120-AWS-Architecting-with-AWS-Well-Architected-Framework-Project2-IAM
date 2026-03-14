#!/bin/bash
# EC2 User Data — runs on first boot
# Sets up the app server environment

set -euo pipefail

# Update system
yum update -y

# Install AWS CLI v2 (already present on Amazon Linux 2023)
# Install useful tools
yum install -y jq python3-pip

# Create the upload script
# This script uses the instance profile — no credentials needed
cat > /home/ec2-user/upload_document.sh << 'SCRIPT'
#!/bin/bash
# Demo: Upload a document to S3 using instance profile credentials
# No AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY needed

BUCKET="${input_bucket}"
REGION="${aws_region}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FILE_PATH="/tmp/sample_$TIMESTAMP.txt"

# Create a sample document
cat > "$FILE_PATH" << DOC
Document: Sample Report $TIMESTAMP
Environment: ${environment}
Server: $(hostname)
Generated: $(date -u)

This document was created by the EC2 app server and uploaded to S3
using an IAM instance profile — no hardcoded credentials required.

The IAM role attached to this instance ONLY allows:
  - s3:PutObject on the input bucket
  - s3:ListBucket on the input bucket

It CANNOT:
  - Read from the output bucket
  - Delete files
  - Access any other AWS service
DOC

echo "Uploading: $FILE_PATH to s3://$BUCKET/uploads/"

aws s3 cp "$FILE_PATH" \
    "s3://$BUCKET/uploads/$(basename $FILE_PATH)" \
    --region "$REGION"

echo "Upload complete. Lambda will now process this file automatically."
SCRIPT

chmod +x /home/ec2-user/upload_document.sh
chown ec2-user:ec2-user /home/ec2-user/upload_document.sh

# Configure AWS CLI region
mkdir -p /home/ec2-user/.aws
cat > /home/ec2-user/.aws/config << CONFIG
[default]
region = ${aws_region}
output = json
CONFIG
chown -R ec2-user:ec2-user /home/ec2-user/.aws

echo "EC2 setup complete — run ~/upload_document.sh to test the pipeline"
