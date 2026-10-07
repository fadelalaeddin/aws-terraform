"""
Processes S3 upload events delivered through SQS.

Flow: S3 -> EventBridge -> SQS -> this Lambda (failures land in the DLQ).
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PROJECT_NAME = os.environ.get("PROJECT_NAME", "unknown-project")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown-environment")


def process_record(record):
    body = json.loads(record["body"])
    detail = body.get("detail", {})

    bucket = detail.get("bucket", {}).get("name", "unknown-bucket")
    obj = detail.get("object", {})
    key = obj.get("key", "unknown-key")
    size = obj.get("size", 0)

    logger.info(
        "[%s/%s] got s3://%s/%s (%s bytes)",
        PROJECT_NAME, ENVIRONMENT, bucket, key, size,
    )

    # TODO: manifest validation / downstream trigger


def lambda_handler(event, context):
    records = event.get("Records", [])
    logger.info("Received %d message(s)", len(records))

    failures = []
    for record in records:
        try:
            process_record(record)
        except Exception:
            msg_id = record.get("messageId")
            logger.exception("Failed to process message %s", msg_id)
            failures.append({"itemIdentifier": msg_id})

    # Only failed messages get retried (needs ReportBatchItemFailures
    # on the event source mapping)
    return {"batchItemFailures": failures}
