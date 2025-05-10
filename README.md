# Lambda + SQS + SNS — Event-Driven Order Processing

A small, hands-on project that shows the **SNS → SQS fan-out pattern** — one of the most common event-driven architectures on AWS.

You place an "order" once, and **three independent services** react in parallel: inventory, notifications, and invoicing. None of them know about each other. That's the whole point.

Runs **100% locally** using [LocalStack](https://localstack.cloud) — no AWS account, no costs.

---

## The Architecture

```
                       ┌──────────────────┐
   place_order.py ───► │ order-api Lambda │
                       └────────┬─────────┘
                                │ publish OrderPlaced event
                                ▼
                  ┌───────────────────────────┐
                  │  SNS Topic: order-placed  │ ← the broadcaster
                  └─────┬───────────┬─────────┘
                        │           │           │
            ┌───────────┘           │           └────────────┐
            ▼                       ▼                        ▼
      ┌──────────┐            ┌──────────┐            ┌──────────┐
      │ SQS:     │            │ SQS:     │            │ SQS:     │ ← buffered mailboxes
      │ inventory│            │ notify   │            │ invoice  │
      └─────┬────┘            └─────┬────┘            └─────┬────┘
            │                       │                       │
            ▼                       ▼                       ▼
   ┌────────────────┐      ┌────────────────┐    ┌────────────────┐
   │ inventory      │      │ notification   │    │ invoice        │ ← workers
   │ Lambda         │      │ Lambda         │    │ Lambda         │
   └────────────────┘      └────────────────┘    └────────────────┘
   (decrement stock)       ("send email")        (create invoice)
```

### Why each piece exists

| Service | Role | What would go wrong without it |
|---|---|---|
| **SNS** | One-to-many broadcaster | Order Lambda would have to know about every downstream service |
| **SQS** | Per-consumer buffered queue | If Inventory Lambda is down or slow, events would be lost |
| **Lambda** | Pay-per-use stateless workers | You'd run idle servers waiting for events |

**Key insight:** Adding a new feature (e.g. an "analytics" service) means *adding one more SQS queue + Lambda*. Zero changes to existing code. That's event-driven decoupling.

---

## Quick Start

Works on **macOS** and **Linux (Ubuntu/Debian)**.

### Prerequisites

- **Docker** (for LocalStack)
- **[uv](https://docs.astral.sh/uv/)** (Python package & project manager)

<details>
<summary>Install on Ubuntu</summary>

```bash
# Docker (using the official convenience script)
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"   # add yourself to the docker group
newgrp docker                     # apply without re-login

# uv
curl -LsSf https://astral.sh/uv/install.sh | sh
exec "$SHELL"                     # reload PATH
```

You may also need `zip` and `curl` (preinstalled on most distros):
`sudo apt update && sudo apt install -y zip curl`

</details>

<details>
<summary>Install on macOS</summary>

```bash
brew install --cask docker         # Docker Desktop
brew install uv
open -a Docker                     # start Docker Desktop
```

</details>

### One-time setup

```bash
# Installs Python 3.12 (if needed) and all deps into .venv from pyproject.toml / uv.lock
uv sync

# Activate the venv so `awslocal` and `python` are on your PATH for this shell
source .venv/bin/activate
```

> Prefer not to activate? Replace every `python ...` below with `uv run python ...`
> and every `awslocal ...` with `uv run awslocal ...`. The shell scripts assume
> the venv is activated (or that `awslocal` is otherwise on `PATH`).

### Run it

```bash
# 1. Start LocalStack (SNS + SQS + Lambda emulator)
docker compose up -d

# 2. Create the topic, queues, subscriptions, and deploy all 4 Lambdas
./scripts/setup.sh

# 3. In one terminal, watch the workers react in real-time
./scripts/watch_logs.sh

# 4. In another terminal (also with venv activated), place an order
python client/place_order.py

# Watch the first terminal — you'll see all 3 services fire simultaneously.
```

### Try things

```bash
# Place a few orders fast
for i in 1 2 3 4 5; do python client/place_order.py; done

# Inspect the queues directly
awslocal sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/inventory-queue \
  --attribute-names ApproximateNumberOfMessages

# List the topic subscriptions (you'll see all 3 SQS queues subscribed)
awslocal sns list-subscriptions
```

### Tear down

```bash
# Full nuke — stops the container, removes its volumes, deletes log groups
# and Lambda runtime containers, removes build artifacts. Workspace is fresh.
./scripts/teardown.sh

# OR — just clear AWS resources but keep LocalStack running (faster redeploys)
./scripts/teardown.sh --soft
```

---

## Project Layout

```
.
├── docker-compose.yml          LocalStack container
├── pyproject.toml              Project metadata + deps (boto3, awscli, awscli-local)
├── uv.lock                     Locked dependency versions (managed by uv)
├── .python-version             Python version pin (3.12, used by uv)
├── lambdas/
│   ├── order_api/              Receives order, publishes to SNS
│   ├── inventory_service/      Decrements stock when order arrives
│   ├── notification_service/   "Sends" confirmation email
│   └── invoice_service/        Creates an invoice record
├── scripts/
│   ├── setup.sh                Builds the whole pipeline
│   ├── watch_logs.sh           Wrapper -> watch_logs.py
│   ├── watch_logs.py           Tails all 4 Lambda log groups (color-coded)
│   └── teardown.sh             Cleans everything up
└── client/
    └── place_order.py          Invokes the order-api Lambda
```

---

## What to Look For

When you place an order and watch the logs, you should see something like this
(each service appears in its own color in the terminal):

```
01:23:45 [            order-api] [order-api] Received order ord-3f9a2b -> publishing to SNS
01:23:46 [    inventory-service] [inventory] Processing order ord-3f9a2b
01:23:46 [    inventory-service] [inventory]   - decrementing stock: SKU=pizza-margherita qty=2
01:23:46 [ notification-service] [notification] Sending confirmation email to alice@example.com for order ord-3f9a2b (total $24.00)
01:23:46 [      invoice-service] [invoice] Generated INV-2026-4471 for order ord-3f9a2b ($24.00)
```

All three downstream services run **in parallel** because SNS delivered the message to all three SQS queues *simultaneously*, and Lambda picked them up independently.

Now imagine you want to add a **fraud-detection** service. You'd:
1. Create one more SQS queue
2. Subscribe it to the SNS topic
3. Deploy one new Lambda

Zero changes to anything that already exists. That's the power of event-driven architecture.
