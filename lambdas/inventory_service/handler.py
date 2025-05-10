"""
inventory-service Lambda
------------------------
Triggered by the `inventory-queue` SQS queue. For each `OrderPlaced` event,
pretends to decrement stock for every item in the order.

Lambda automatically polls SQS and delivers messages in batches via the `Records` key.
"""
import json


def handler(event, context):
    for record in event.get("Records", []):
        # SNS-to-SQS messages arrive wrapped in an SNS envelope.
        body = json.loads(record["body"])
        order = json.loads(body["Message"]) if "Message" in body else body

        print(f"[inventory] Processing order {order['order_id']}")
        for item in order.get("items", []):
            sku = item.get("sku", "unknown")
            qty = item.get("qty", 1)
            print(f"[inventory]   - decrementing stock: SKU={sku} qty={qty}")

    return {"processed": len(event.get("Records", []))}
