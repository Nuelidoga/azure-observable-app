#!/usr/bin/env bash
# Post-deploy smoke test. Usage: scripts/smoke_test.sh <base-url>
# Retries generously: the app may scale from zero and the serverless database may resume.
set -euo pipefail
BASE="${1:?usage: scripts/smoke_test.sh <base-url>}"; BASE="${BASE%/}"

retry() {  # retry <description> <command...>
  local desc="$1"; shift
  for i in $(seq 1 18); do
    if "$@" >/dev/null 2>&1; then echo "PASS: $desc"; return 0; fi
    echo "  waiting ($i/18): $desc"; sleep 10
  done
  echo "FAIL: $desc"; return 1
}

TITLE="smoke-$(date +%s)"
retry "GET /health"  curl -fsS --max-time 30 "$BASE/health"
retry "GET /ready (database reachable via managed identity)" curl -fsS --max-time 60 "$BASE/ready"
retry "POST /tasks" curl -fsS --max-time 30 -X POST "$BASE/tasks" -H 'Content-Type: application/json' -d "{\"title\":\"$TITLE\"}"
retry "task round-trip" bash -c "curl -fsS --max-time 30 '$BASE/tasks' | grep -q '$TITLE'"
echo "Smoke test passed for $BASE"
