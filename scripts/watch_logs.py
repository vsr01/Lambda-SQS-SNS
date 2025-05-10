"""
watch_logs.py — tails the CloudWatch log groups of all four Lambdas in one
unified, color-coded stream so you can watch the event flow in real time.

Why Python and not `aws logs tail`? `aws logs tail --follow` is an AWS CLI v2
feature and we're on v1 in this project. boto3 is already a dependency, so a
20-line poller is portable, dependency-free, and works on macOS/Linux/CI alike.
"""
import sys
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

LOCALSTACK = "http://localhost:4566"
LAMBDAS = ["order-api", "inventory-service", "notification-service", "invoice-service"]
POLL_INTERVAL = 1.0  # seconds

COLORS = {
    "order-api":            "\033[36m",  # cyan
    "inventory-service":    "\033[33m",  # yellow
    "notification-service": "\033[35m",  # magenta
    "invoice-service":      "\033[32m",  # green
}
RESET = "\033[0m"


def main():
    logs = boto3.client(
        "logs", endpoint_url=LOCALSTACK, region_name="us-east-1",
        aws_access_key_id="test", aws_secret_access_key="test",
    )

    for fn in LAMBDAS:
        try:
            logs.create_log_group(logGroupName=f"/aws/lambda/{fn}")
        except ClientError:
            pass  # Already exists.

    print(f"Tailing logs for: {', '.join(LAMBDAS)}")
    print("Press Ctrl-C to stop.\n")

    # Start "now" so we only show events that happen after the watcher starts.
    last_seen_ms = {fn: int(time.time() * 1000) for fn in LAMBDAS}

    try:
        while True:
            for fn in LAMBDAS:
                group = f"/aws/lambda/{fn}"
                try:
                    resp = logs.filter_log_events(
                        logGroupName=group,
                        startTime=last_seen_ms[fn] + 1,
                    )
                except ClientError:
                    continue

                for event in resp.get("events", []):
                    ts = datetime.fromtimestamp(
                        event["timestamp"] / 1000, tz=timezone.utc
                    ).strftime("%H:%M:%S")
                    msg = event["message"].rstrip("\n")
                    # Skip the noisy AWS Lambda runtime START/END/REPORT lines.
                    if msg.startswith(("START RequestId", "END RequestId", "REPORT RequestId")):
                        continue
                    color = COLORS.get(fn, "")
                    print(f"{color}{ts} [{fn:>21}]{RESET} {msg}")
                    last_seen_ms[fn] = max(last_seen_ms[fn], event["timestamp"])

            time.sleep(POLL_INTERVAL)
    except KeyboardInterrupt:
        print("\nStopping...")
        return 0


if __name__ == "__main__":
    sys.exit(main())
