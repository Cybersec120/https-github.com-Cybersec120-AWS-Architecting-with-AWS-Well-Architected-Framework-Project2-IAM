# Project 2 — Security (IAM)
## AWS Well-Architected Framework | Pillar 2

![Architecture Diagram](./diagram.jpg)

---

## Overview

This project builds a **secure document processing pipeline** on AWS, demonstrating real-world IAM least privilege design across three different AWS principals: an EC2 app server, a Lambda function, and CloudTrail.

Every component has **exactly the permissions it needs — nothing more.** This is enforced at two layers simultaneously: IAM policies AND S3 bucket policies.

---

## Architecture

### The Pipeline

```
EC2 App Server  →  S3 Input Bucket  →  Lambda Processor  →  S3 Output Bucket
  (upload)           (event trigger)        (transform)          (results)
```

1. **EC2** uploads a `.txt` document to the input S3 bucket using its instance profile — no credentials stored on the machine
2. **S3** fires an event notification to Lambda when a file lands in `uploads/`
3. **Lambda** reads the file, processes it, and writes a JSON result to the output bucket
4. **CloudTrail** records every API call in the entire pipeline for auditing
5. **CloudWatch alarms** fire if unauthorized access or IAM changes are detected

---

## IAM Design — The Core of This Project

### Three Principals. Three Roles. Zero Shared Permissions.

| Principal | IAM Role | Allowed Actions | Explicitly Denied |
|---|---|---|---|
| **EC2** | `ec2-role` | `s3:PutObject` on input bucket | Cannot touch output bucket |
| **Lambda** | `lambda-role` | `s3:GetObject` on input, `s3:PutObject` on output | Cannot delete, cannot access any other service |
| **CloudTrail** | `cloudtrail-role` | `logs:PutLogEvents` to its CloudWatch group | Nothing else |

### Why Two Layers of Enforcement?

IAM policies alone can be bypassed if roles are misconfigured or over-permissive. Bucket policies provide a **second independent enforcement layer** at the resource level:

```
Request arrives at S3
    ↓
IAM policy check:  Does this role have permission?
    ↓
Bucket policy check: Does this bucket allow this principal?
    ↓
BOTH must allow the action — either one can deny it
```

The output bucket **explicitly denies EC2** at the bucket policy level — even if someone accidentally broadened the EC2 role, the bucket policy blocks it.

---

## Security Highlights

### No Hardcoded Credentials — Ever
EC2 uses an **IAM Instance Profile**. The AWS SDK on the instance automatically retrieves temporary credentials from the instance metadata service. No `AWS_ACCESS_KEY_ID`. No `AWS_SECRET_ACCESS_KEY`. Nothing to leak, rotate, or accidentally commit.

### IMDSv2 Enforced
The EC2 instance is configured to require **IMDSv2** (token-based metadata requests):
```hcl
metadata_options {
  http_tokens                 = "required"   # IMDSv2 only
  http_put_response_hop_limit = 1            # Blocks container escape attacks
}
```
IMDSv1 is disabled — this prevents SSRF attacks from stealing instance credentials.

### Lambda Confused Deputy Protection
The S3 → Lambda permission is scoped to a specific account:
```hcl
source_account = data.aws_caller_identity.current.account_id
```
This prevents a confused deputy attack where a different account's S3 bucket tricks your Lambda into executing.

### Dead Letter Queue
Failed Lambda invocations are sent to an SQS Dead Letter Queue rather than silently dropped. This ensures no events are lost and failed processing can be investigated and retried.

---

## Audit & Detection

### CloudTrail
A CloudTrail trail is deployed capturing:
- All **management events** (IAM changes, resource creation/deletion)
- **S3 data events** on both buckets (who accessed which objects, when)
- **Lambda invocation events**

Logs are stored in a dedicated encrypted S3 bucket with a 90-day lifecycle policy. Log file validation is enabled to detect tampering.

### Security Alarms

| Alarm | Trigger | Meaning |
|---|---|---|
| `unauthorized-api-calls` | Any `AccessDenied` or `UnauthorizedAccess` error | Credential abuse attempt or misconfiguration |
| `iam-policy-changes` | Any IAM policy attach/detach/modify | Privilege escalation attempt |

Both alarms fire to a dedicated SNS security alerts topic.

---

## Well-Architected Alignment

### Security Pillar — Design Principles Applied

**1. Implement a strong identity foundation**
Every AWS principal uses an IAM role with a specific trust policy. No IAM users with long-term access keys are used in the pipeline. All roles are defined in code and peer-reviewable.

**2. Apply least-privilege permissions**
Permissions are scoped to specific resources (bucket ARNs), specific actions (only what's needed), and enforced at two independent layers (IAM + bucket policy). No wildcards (`*`) in resource ARNs or actions.

**3. Enable traceability**
CloudTrail captures every API call. CloudWatch metric filters parse those logs for security-relevant events. Alarms fire immediately on anomalies. All logs are retained for 90 days.

**4. Automate security best practices**
Security is defined in Terraform — not clicked together in the console. IMDSv2 enforcement, encryption, log validation, and DLQ configuration are all automated. No human can forget to enable them.

**5. Protect data in transit and at rest**
All S3 buckets use AES-256 server-side encryption. All bucket versioning is enabled. Public access is blocked at both the bucket and account level. SNS and SQS topics are encrypted with AWS managed keys.

---

## Project Structure

```
project-2-security-iam/
├── providers.tf              # AWS provider configuration
├── variables.tf              # Input variables with validation
├── iam.tf                    # All IAM roles, policies, instance profile
├── s3.tf                     # Input, output, and CloudTrail log buckets
├── ec2.tf                    # App server with instance profile
├── lambda.tf                 # Processor function, DLQ, S3 permission
├── cloudtrail.tf             # Audit trail, CW alarms, SNS topic
├── outputs.tf                # Resource IDs and test commands
├── userdata.sh               # EC2 bootstrap script
├── terraform.tfvars.example  # Variable template
├── .gitignore
├── diagram.jpg               # Architecture diagram
├── README.md                 # This file
└── lambda/
    └── processor.py          # Python Lambda function
```

---

## Prerequisites

- [Terraform](https://developer.hashicorp.com/terraform/install) >= 1.5.0
- [AWS CLI](https://aws.amazon.com/cli/) configured
- IAM permissions for: EC2, Lambda, S3, IAM, CloudTrail, CloudWatch, SNS, SQS

---

## Deployment

```bash
# 1. Clone and navigate
git clone https://github.com/YOUR_USERNAME/aws-well-architected-projects
cd project-2-security-iam

# 2. Configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars — set your IP for allowed_ssh_cidr

# 3. Deploy
terraform init
terraform plan
terraform apply

# 4. Test the pipeline
ssh ec2-user@<EC2_PUBLIC_IP> '~/upload_document.sh'

# 5. Watch Lambda process it
aws logs tail /aws/lambda/security-iam-demo-processor --follow
```

---

## Testing Least Privilege

After deployment, verify the IAM boundaries work:

```bash
# SSH to EC2 and try to read the output bucket — should be DENIED
ssh ec2-user@<EC2_IP>
aws s3 ls s3://<OUTPUT_BUCKET>/   # AccessDenied — as designed

# Upload a file — should SUCCEED
~/upload_document.sh

# Check Lambda processed it
aws s3 ls s3://<OUTPUT_BUCKET>/processed/ --region us-east-1
```

---

## Cleanup

```bash
terraform destroy
```

---

## Cost Estimate

| Service | Est. Monthly Cost |
|---|---|
| EC2 t3.micro | ~$8.50 |
| Lambda (low invocations) | < $0.01 |
| S3 (3 buckets, minimal data) | < $0.10 |
| CloudTrail | < $2.00 |
| CloudWatch | < $1.00 |
| SQS DLQ | < $0.01 |
| **Total** | **~$12/month** |

> Stop the EC2 instance when not actively testing to reduce costs.

---

## Author

Mr Shabazz El Built as a portfolio project demonstrating the **AWS Well-Architected Framework — Security Pillar**.

Technologies: `Terraform` `AWS IAM` `Amazon EC2` `AWS Lambda` `Amazon S3` `AWS CloudTrail` `Amazon CloudWatch` `Amazon SNS` `Amazon SQS`
