#!/usr/bin/env bash
# Break the app on purpose to trigger alerts (needs ENABLE_CHAOS=true).
# Usage: scripts/chaos.sh <base-url> <error|crash>
set -euo pipefail
BASE="${1:?usage: scripts/chaos.sh <base-url> <error|crash>}"; BASE="${BASE%/}"
case "${2:?mode required: error|crash}" in
  error) for i in $(seq 1 60); do curl -s -o /dev/null -w "%{http_code} " "$BASE/chaos/error"; sleep 1; done; echo
         echo "Sent 60 failing requests. The 5xx alert evaluates every minute over a 5-minute window." ;;
  crash) curl -s -o /dev/null -w "%{http_code}\n" "$BASE/chaos/crash" || true
         echo "Crash requested. Expect a restart alert within a few minutes." ;;
  *) echo "unknown mode"; exit 1 ;;
esac
