#!/usr/bin/env bash
# Full nuke: stops the LocalStack container, removes its volumes, removes any
# Lambda runtime containers/images LocalStack spawned, and cleans local
# build artifacts. After this, the workspace is back to a fresh state.
#
# Run with --soft to only delete AWS resources but keep the container running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LAMBDAS=(order-api inventory-service notification-service invoice-service)
QUEUES=(inventory-queue notification-queue invoice-queue)

soft_teardown () {
  echo "==> Deleting event source mappings"
  for fn in "${LAMBDAS[@]}"; do
    uuids=$(awslocal lambda list-event-source-mappings \
      --function-name "$fn" \
      --query 'EventSourceMappings[].UUID' --output text 2>/dev/null || true)
    for uuid in $uuids; do
      [[ -n "$uuid" && "$uuid" != "None" ]] && \
        awslocal lambda delete-event-source-mapping --uuid "$uuid" >/dev/null 2>&1 || true
    done
  done

  echo "==> Deleting Lambda functions"
  for fn in "${LAMBDAS[@]}"; do
    awslocal lambda delete-function --function-name "$fn" 2>/dev/null || true
  done

  echo "==> Deleting SQS queues"
  for q in "${QUEUES[@]}"; do
    url=$(awslocal sqs get-queue-url --queue-name "$q" --query QueueUrl --output text 2>/dev/null || true)
    [[ -n "$url" && "$url" != "None" ]] && \
      awslocal sqs delete-queue --queue-url "$url" >/dev/null 2>&1 || true
  done

  echo "==> Deleting SNS topic (and its subscriptions)"
  topic_arn=$(awslocal sns list-topics \
    --query "Topics[?contains(TopicArn, 'order-placed')].TopicArn" --output text 2>/dev/null || true)
  [[ -n "$topic_arn" && "$topic_arn" != "None" ]] && \
    awslocal sns delete-topic --topic-arn "$topic_arn" >/dev/null 2>&1 || true

  echo "==> Deleting CloudWatch log groups"
  for fn in "${LAMBDAS[@]}"; do
    awslocal logs delete-log-group --log-group-name "/aws/lambda/$fn" 2>/dev/null || true
  done
}

if [[ "${1:-}" == "--soft" ]]; then
  echo "Soft teardown — keeping LocalStack container running."
  soft_teardown
  echo ""
  echo "Done. Re-run ./scripts/setup.sh to redeploy."
  exit 0
fi

# ---------------------------------------------------------------------------
# Full nuke
# ---------------------------------------------------------------------------
echo "==> Full teardown — removing everything."

# Best-effort soft cleanup first (only if LocalStack is reachable). This
# triggers any in-flight event drains before we kill the container.
if curl -sf http://localhost:4566/_localstack/health >/dev/null 2>&1; then
  soft_teardown
fi

echo "==> Removing Lambda runtime containers spawned by LocalStack"
# LocalStack tags every Lambda runtime container it creates with `localstack=true`.
runtime_ids=$(docker ps -aq --filter "label=localstack=true" 2>/dev/null || true)
[[ -n "$runtime_ids" ]] && docker rm -f $runtime_ids >/dev/null 2>&1 || true

echo "==> Stopping LocalStack container and removing its volumes"
docker compose down -v --remove-orphans >/dev/null 2>&1 || \
  docker-compose down -v --remove-orphans >/dev/null 2>&1 || true

echo "==> Removing local build artifacts"
rm -f /tmp/order-api.zip /tmp/inventory-service.zip \
      /tmp/notification-service.zip /tmp/invoice-service.zip

echo ""
echo "Everything is gone. Workspace is back to a fresh state."
echo "To start over:"
echo "  docker compose up -d && ./scripts/setup.sh"
