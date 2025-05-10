#!/usr/bin/env bash
# Wires up the entire event-driven pipeline on LocalStack.
#
#   SNS topic  ──fan-out──► 3 SQS queues ──trigger──► 3 Lambda functions
#                                              also: 1 publisher Lambda (order-api)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

REGION="us-east-1"
ACCOUNT="000000000000"  # LocalStack's fixed mock account ID
ROLE_ARN="arn:aws:iam::${ACCOUNT}:role/lambda-role"

echo "==> Waiting for LocalStack to be ready..."
# LocalStack reports services as "available" before first use and "running" after,
# so accept either state. Without this, re-runs hang because SNS is already running.
until curl -s http://localhost:4566/_localstack/health | grep -qE '"sns": "(available|running)"'; do
  sleep 1
done
echo "    LocalStack is up."

# ---------------------------------------------------------------------------
# 1. SNS TOPIC — the broadcaster
# ---------------------------------------------------------------------------
echo "==> Creating SNS topic: order-placed"
TOPIC_ARN=$(awslocal sns create-topic --name order-placed --query TopicArn --output text)
echo "    $TOPIC_ARN"

# ---------------------------------------------------------------------------
# 2. SQS QUEUES — one per consumer (the buffered mailboxes)
# ---------------------------------------------------------------------------
declare -a QUEUES=("inventory-queue" "notification-queue" "invoice-queue")

for q in "${QUEUES[@]}"; do
  echo "==> Creating SQS queue: $q"
  awslocal sqs create-queue --queue-name "$q" >/dev/null
done

# ---------------------------------------------------------------------------
# 3. SUBSCRIBE each queue to the topic + grant SNS permission to write to it
# ---------------------------------------------------------------------------
for q in "${QUEUES[@]}"; do
  QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT}:${q}"
  QUEUE_URL="http://localhost:4566/${ACCOUNT}/${q}"

  echo "==> Subscribing $q to topic"
  # Use shorthand syntax (Key=Value) — `--attributes` does NOT accept inline JSON.
  awslocal sns subscribe \
    --topic-arn "$TOPIC_ARN" \
    --protocol sqs \
    --notification-endpoint "$QUEUE_ARN" \
    --attributes RawMessageDelivery=false >/dev/null

  # Allow the SNS topic to send messages into this SQS queue.
  # The IAM policy contains commas, which would break shorthand parsing,
  # so we hand the AWS CLI a file:// reference instead.
  ATTR_FILE=$(mktemp)
  cat > "$ATTR_FILE" <<EOF
{
  "Policy": "{\"Version\":\"2012-10-17\",\"Statement\":[{\"Effect\":\"Allow\",\"Principal\":{\"Service\":\"sns.amazonaws.com\"},\"Action\":\"sqs:SendMessage\",\"Resource\":\"${QUEUE_ARN}\",\"Condition\":{\"ArnEquals\":{\"aws:SourceArn\":\"${TOPIC_ARN}\"}}}]}"
}
EOF
  awslocal sqs set-queue-attributes \
    --queue-url "$QUEUE_URL" \
    --attributes "file://$ATTR_FILE" >/dev/null
  rm -f "$ATTR_FILE"
done

# ---------------------------------------------------------------------------
# 4. PACKAGE & DEPLOY the four Lambda functions
# ---------------------------------------------------------------------------
deploy_lambda () {
  local name="$1"        # e.g. inventory-service
  local src_dir="$2"     # e.g. lambdas/inventory_service
  local env_vars="$3"    # e.g. "Variables={TOPIC_ARN=...}" or empty

  local zipfile="/tmp/${name}.zip"
  ( cd "$src_dir" && rm -f "$zipfile" && zip -qr "$zipfile" . )

  echo "==> Deploying Lambda: $name"
  if awslocal lambda get-function --function-name "$name" >/dev/null 2>&1; then
    awslocal lambda update-function-code \
      --function-name "$name" --zip-file "fileb://$zipfile" >/dev/null
    if [[ -n "$env_vars" ]]; then
      awslocal lambda update-function-configuration \
        --function-name "$name" --environment "$env_vars" >/dev/null
    fi
  else
    # Use ${arr[@]+"${arr[@]}"} so an empty array doesn't trip `set -u`
    # on macOS's Bash 3.2.
    local extra=()
    [[ -n "$env_vars" ]] && extra=(--environment "$env_vars")
    awslocal lambda create-function \
      --function-name "$name" \
      --runtime python3.11 \
      --role "$ROLE_ARN" \
      --handler handler.handler \
      --zip-file "fileb://$zipfile" \
      ${extra[@]+"${extra[@]}"} >/dev/null
  fi

  awslocal lambda wait function-active-v2 --function-name "$name"
}

deploy_lambda "order-api"            "lambdas/order_api"            "Variables={TOPIC_ARN=${TOPIC_ARN}}"
deploy_lambda "inventory-service"    "lambdas/inventory_service"    ""
deploy_lambda "notification-service" "lambdas/notification_service" ""
deploy_lambda "invoice-service"      "lambdas/invoice_service"      ""

# ---------------------------------------------------------------------------
# 5. WIRE SQS QUEUES as event sources for the worker Lambdas
# ---------------------------------------------------------------------------
# Two parallel indexed arrays (Bash 3.2 on macOS doesn't have associative arrays).
QUEUE_NAMES=("inventory-queue" "notification-queue" "invoice-queue")
LAMBDA_NAMES=("inventory-service" "notification-service" "invoice-service")

for i in "${!QUEUE_NAMES[@]}"; do
  q="${QUEUE_NAMES[$i]}"
  fn="${LAMBDA_NAMES[$i]}"
  QUEUE_ARN="arn:aws:sqs:${REGION}:${ACCOUNT}:${q}"

  # Avoid creating duplicate event source mappings on re-runs.
  existing=$(awslocal lambda list-event-source-mappings \
    --function-name "$fn" \
    --query "EventSourceMappings[?EventSourceArn=='${QUEUE_ARN}'].UUID" \
    --output text)

  if [[ -z "$existing" ]]; then
    echo "==> Wiring $q ──trigger──► $fn"
    awslocal lambda create-event-source-mapping \
      --function-name "$fn" \
      --batch-size 5 \
      --event-source-arn "$QUEUE_ARN" >/dev/null
  fi
done

echo ""
echo "============================================================"
echo " Pipeline ready."
echo ""
echo " Try it now:"
echo "   ./scripts/watch_logs.sh         (in one terminal)"
echo "   python client/place_order.py    (in another)"
echo "============================================================"
