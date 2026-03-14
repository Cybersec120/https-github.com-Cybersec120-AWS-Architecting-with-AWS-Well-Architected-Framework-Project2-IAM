# ─────────────────────────────────────────────────────────────────
# EC2 — App Server
# Uses an instance profile — ZERO hardcoded credentials
# Can only upload to input bucket — enforced at both IAM and S3 policy
# ─────────────────────────────────────────────────────────────────

# Security Group — minimal ingress
resource "aws_security_group" "ec2" {
  name        = "${var.project_name}-ec2-sg"
  description = "App server security group — SSH only from allowed CIDR"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from allowed CIDR only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow all outbound — needed for AWS API calls and updates"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-ec2-sg" }
}

# EC2 Instance — uses instance profile, no access keys
resource "aws_instance" "app_server" {
  ami                    = var.ec2_ami
  instance_type          = var.ec2_instance_type
  iam_instance_profile   = aws_iam_instance_profile.ec2_profile.name
  vpc_security_group_ids = [aws_security_group.ec2.id]

  # IMDSv2 enforced — prevents SSRF attacks stealing instance credentials
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # IMDSv2 only — no IMDSv1
    http_put_response_hop_limit = 1           # Container escape protection
  }

  # Encrypted root volume
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true
  }

  # User data — installs AWS CLI and demo upload script
  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    input_bucket = aws_s3_bucket.input.id
    environment  = var.environment
    project_name = var.project_name
    aws_region   = var.aws_region
  }))

  tags = { Name = "${var.project_name}-app-server" }
}

# Use default VPC for simplicity in this demo
# In production: build a proper VPC with private subnets
data "aws_vpc" "default" {
  default = true
}
