"""
notification-service Lambda
---------------------------
Triggered by the `notification-queue` SQS queue. "Sends" a confirmation email
(here: just logs it) for every order.
"""
import json


def handler(event, context):
    for record in event.get("Records", []):
        body = json.loads(record["body"])
        order = json.loads(body["Message"]) if "Message" in body else body

        email = order.get("customer_email", "unknown")
        print(
            f"[notification] Sending confirmation email to {email} "
            f"for order {order['order_id']} (total ${order.get('total', 0):.2f})"
        )

    return {"sent": len(event.get("Records", []))}
