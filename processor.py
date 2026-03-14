"""
Document Processor Lambda
─────────────────────────
Triggered by: S3 ObjectCreated event (input bucket)
Reads:        Raw .txt file from input bucket
Writes:       Processed result to output bucket
IAM:          Least privilege — only the permissions it needs, nothing more

Security notes:
  - No hardcoded credentials
  - Uses IAM role via STS (automatic via Lambda execution role)
  - Logs sanitized — no sensitive data written to CloudWatch
  - Input validated before processing
"""

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ── Logging ──────────────────────────────────────────────────────
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
logger = logging.getLogger()
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))

# ── Config ───────────────────────────────────────────────────────
OUTPUT_BUCKET = os.environ["OUTPUT_BUCKET"]
ENVIRONMENT   = os.environ.get("ENVIRONMENT", "production")

# ── AWS clients ──────────────────────────────────────────────────
s3 = boto3.client("s3")


def lambda_handler(event, context):
    """
    Entry point. Triggered by S3 event notification.
    """
    logger.info("Processor invoked — records: %d", len(event.get("Records", [])))

    results = []
    for record in event["Records"]:
        result = process_record(record)
        results.append(result)

    success_count = sum(1 for r in results if r["status"] == "success")
    logger.info("Completed — %d/%d succeeded", success_count, len(results))

    return {
        "statusCode": 200,
        "body": json.dumps({
            "processed": len(results),
            "succeeded": success_count,
            "failed": len(results) - success_count
        })
    }


def process_record(record):
    """
    Process a single S3 event record.
    """
    source_bucket = record["s3"]["bucket"]["name"]
    object_key    = urllib.parse.unquote_plus(
        record["s3"]["object"]["key"], encoding="utf-8"
    )
    object_size   = record["s3"]["object"].get("size", 0)

    logger.info("Processing: bucket=%s key=%s size=%d bytes",
                source_bucket, object_key, object_size)

    # Guard: reject suspiciously large files (>10MB)
    if object_size > 10 * 1024 * 1024:
        logger.warning("File too large — skipping: %s (%d bytes)", object_key, object_size)
        return {"status": "skipped", "reason": "file_too_large", "key": object_key}

    try:
        # Read the file from input bucket
        response = s3.get_object(Bucket=source_bucket, Key=object_key)
        raw_content = response["Body"].read().decode("utf-8", errors="replace")

        # Process the document
        processed = transform_document(raw_content, object_key)

        # Write result to output bucket
        output_key = build_output_key(object_key)
        s3.put_object(
            Bucket=OUTPUT_BUCKET,
            Key=output_key,
            Body=json.dumps(processed, indent=2),
            ContentType="application/json",
            ServerSideEncryption="AES256",
            Metadata={
                "source-key":    object_key,
                "source-bucket": source_bucket,
                "environment":   ENVIRONMENT,
                "processed-at":  datetime.now(timezone.utc).isoformat()
            }
        )

        logger.info("Written to output: %s", output_key)
        return {"status": "success", "input": object_key, "output": output_key}

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        logger.error("S3 ClientError [%s] for key=%s", error_code, object_key)
        raise  # Re-raise so Lambda sends to DLQ

    except Exception as e:
        logger.error("Unexpected error processing %s: %s", object_key, type(e).__name__)
        raise


def transform_document(content: str, source_key: str) -> dict:
    """
    Core transformation logic.
    Extend this with your real business logic.
    """
    lines      = [ln.strip() for ln in content.splitlines() if ln.strip()]
    word_count = sum(len(ln.split()) for ln in lines)
    char_count = len(content)

    return {
        "metadata": {
            "source_key":    source_key,
            "environment":   ENVIRONMENT,
            "processed_at":  datetime.now(timezone.utc).isoformat(),
            "line_count":    len(lines),
            "word_count":    word_count,
            "char_count":    char_count,
        },
        "summary": {
            "first_line":    lines[0] if lines else "",
            "last_line":     lines[-1] if lines else "",
            "total_lines":   len(lines),
        },
        "status": "processed"
    }


def build_output_key(input_key: str) -> str:
    """
    Build output path from input key.
    uploads/myfile.txt → processed/2026/03/14/myfile.json
    """
    filename     = input_key.split("/")[-1].rsplit(".", 1)[0]
    now          = datetime.now(timezone.utc)
    return f"processed/{now.year}/{now.month:02d}/{now.day:02d}/{filename}.json"
