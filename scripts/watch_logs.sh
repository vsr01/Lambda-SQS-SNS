#!/usr/bin/env bash
# Thin wrapper around watch_logs.py — the Python implementation is portable
# (works with AWS CLI v1, no dependency on `aws logs tail` which is v2-only,
# no dependency on `sed -u` which is GNU-only).
set -euo pipefail
exec python3 "$(dirname "${BASH_SOURCE[0]}")/watch_logs.py" "$@"
