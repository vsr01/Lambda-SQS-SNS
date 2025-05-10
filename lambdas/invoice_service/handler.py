"""
invoice-service Lambda
----------------------
Triggered by the `invoice-queue` SQS queue. Generates a fake invoice number
and "stores" it (logs it) for every order.
"""
import json
import random


def handler(event, context):
    for record in event.get("Records", []):
        body = json.loads(record["body"])
        order = json.loads(body["Message"]) if "Message" in body else body

        invoice_no = f"INV-2026-{random.randint(1000, 9999)}"
        print(
            f"[invoice] Generated {invoice_no} for order {order['order_id']} "
            f"(${order.get('total', 0):.2f})"
        )

    return {"invoiced": len(event.get("Records", []))}
