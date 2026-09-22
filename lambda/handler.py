"""
event_processor Lambda function.

Event-driven pipeline:
  S3 (Object Created) -> EventBridge rule -> SQS queue -> this Lambda
                                                  |
                                                  v (after N failed attempts)
                                          Dead-letter queue

AWS Lambda's SQS event source mapping polls the queue and invokes this
function with a *batch* of messages. Each message body is the
EventBridge "Object Created" event, JSON-encoded by EventBridge before
it was placed on the queue.

Partial-batch failure handling: this function returns
`batchItemFailures` for any message it could not process, so only the
failed messages go back on the queue for retry (successful ones in the
same batch are NOT redelivered). This requires
`function_response_types = ["ReportBatchItemFailures"]` on the event
source mapping, which is set in Terraform.
"""

import json
import logging
import os

logger = logging.getLogger()
logger.setLevel(logging.INFO)

PROJECT_NAME = os.environ.get("PROJECT_NAME", "unknown-project")
ENVIRONMENT = os.environ.get("ENVIRONMENT", "unknown-environment")


def _process_record(record):
    """
    Process a single SQS record (which wraps one EventBridge S3 event).

    Raises an exception if the record cannot be processed, so the
    caller can report it as a batch item failure.
    """
    message_id = record.get("messageId", "unknown-message-id")
    body = json.loads(record["body"])

    detail = body.get("detail", {})
    bucket_name = detail.get("bucket", {}).get("name", "unknown-bucket")
    object_key = detail.get("object", {}).get("key", "unknown-key")
    object_size = detail.get("object", {}).get("size", 0)

    logger.info(
        "Processing message_id=%s bucket=%s key=%s size=%s bytes (%s/%s)",
        message_id,
        bucket_name,
        object_key,
        object_size,
        PROJECT_NAME,
        ENVIRONMENT,
    )

    # Real processing logic (e.g. kicking off a downstream pipeline step,
    # validating a sequencing run manifest, etc.) would go here.


def lambda_handler(event, context):
    """
    Entry point invoked by the SQS event source mapping.

    `event["Records"]` is a batch of SQS messages (up to batch_size,
    configured in Terraform). Returns `batchItemFailures` for any
    message that failed to process, so Lambda only retries those.
    """
    records = event.get("Records", [])
    logger.info("Received batch of %d message(s)", len(records))

    batch_item_failures = []

    for record in records:
        try:
            _process_record(record)
        except Exception:
            message_id = record.get("messageId", "unknown-message-id")
            logger.exception("Failed to process message_id=%s", message_id)
            batch_item_failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": batch_item_failures}
