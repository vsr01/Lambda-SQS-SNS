"""
place_order.py — invokes the order-api Lambda directly with a fake order.

In a real system you'd put API Gateway in front of order-api and POST JSON over
HTTP. Direct Lambda invocation keeps this demo dependency-free.
"""
import json
import random
import sys

import boto3

LOCALSTACK = "http://localhost:4566"

CATALOG = [
    {"sku": "pizza-margherita",  "name": "Margherita",  "price":  9.50},
    {"sku": "pizza-pepperoni",   "name": "Pepperoni",   "price": 11.00},
    {"sku": "pizza-quattro",     "name": "Quattro Formaggi", "price": 12.50},
    {"sku": "drink-cola",        "name": "Cola",        "price":  2.50},
    {"sku": "side-garlic-bread", "name": "Garlic Bread", "price":  4.00},
]

CUSTOMERS = [
    "alice@example.com", "bob@example.com", "carol@example.com",
    "dan@example.com", "eve@example.com",
]


def build_random_order():
    items = []
    total = 0.0
    for product in random.sample(CATALOG, k=random.randint(1, 3)):
        qty = random.randint(1, 3)
        items.append({"sku": product["sku"], "qty": qty})
        total += product["price"] * qty
    return {
        "customer_email": random.choice(CUSTOMERS),
        "items": items,
        "total": round(total, 2),
    }


def main():
    lam = boto3.client("lambda", endpoint_url=LOCALSTACK, region_name="us-east-1",
                       aws_access_key_id="test", aws_secret_access_key="test")

    order = build_random_order()
    print(f"Placing order: {json.dumps(order, indent=2)}")

    resp = lam.invoke(
        FunctionName="order-api",
        InvocationType="RequestResponse",
        Payload=json.dumps(order).encode(),
    )
    payload = json.loads(resp["Payload"].read())
    print(f"\norder-api responded: {payload}")
    print("\nNow check your watch_logs.sh terminal -- all 3 services should react.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
