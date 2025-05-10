"""
order-api Lambda
----------------
Entry point of the system. Receives an order payload (from a client invocation),
validates it minimally, and PUBLISHES an `OrderPlaced` event to the SNS topic.

That single publish fans out to every subscribed SQS queue (inventory, notification,
invoice) without this function knowing or caring who is listening.
"""
import json
import os
import uuid
from datetime import datetime, timezone

import boto3

# When running inside LocalStack's Lambda runtime, point boto3 at the LocalStack edge.
# `localhost.localstack.cloud` is a special hostname LocalStack DNS-resolves
# from inside Lambda containers — works the same on macOS and Linux,
# unlike `host.docker.internal` which is Docker-Desktop-only.
ENDPOINT_URL = os.environ.get("AWS_ENDPOINT_URL", "http://localhost.localstack.cloud:4566")
TOPIC_ARN = os.environ["TOPIC_ARN"]

sns = boto3.client("sns", endpoint_url=ENDPOINT_URL, region_name="us-east-1")


def handler(event, context):
    order_id = f"ord-{uuid.uuid4().hex[:8]}"
    order = {
        "order_id": order_id,
        "customer_email": event.get("customer_email", "anonymous@example.com"),
        "items": event.get("items", []),
        "total": event.get("total", 0.0),
        "placed_at": datetime.now(timezone.utc).isoformat(),
    }

    print(f"[order-api] Received order {order_id} -> publishing to SNS")

    sns.publish(
        TopicArn=TOPIC_ARN,
        Subject="OrderPlaced",
        Message=json.dumps(order),
        MessageAttributes={
            "event_type": {"DataType": "String", "StringValue": "OrderPlaced"}
        },
    )

    return {"statusCode": 200, "order_id": order_id}
