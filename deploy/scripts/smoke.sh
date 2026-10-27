#!/usr/bin/env bash
# deploy/scripts/smoke.sh - post-deploy smoke test. Read-only.
#
# Usage: bash deploy/scripts/smoke.sh <url> [expected_status=200] [retries=30] [sleep_seconds=2]
# Env:   EXPECT_BODY=<fixed string that must appear in the response body>   (optional)
#        MAX_LATENCY_MS=<fail if a successful response is slower than this>  (optional)
#
# Retries until the URL returns the expected status (a deployment needs time to become ready),
# then checks the optional body / latency expectations. Exit 0 = healthy, 1 = unhealthy.
set -uo pipefail

url="${1:-}"
want="${2:-200}"
retries="${3:-30}"
pause="${4:-2}"
[ -n "$url" ] || { echo "usage: smoke.sh <url> [status] [retries] [sleep]" >&2; exit 2; }
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 2; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

attempt=0
while [ "$attempt" -lt "$retries" ]; do
  attempt=$((attempt + 1))
  out="$(curl -sS -o "$tmp" -w '%{http_code} %{time_total}' --max-time 10 "$url" 2>/dev/null || true)"
  code="${out%% *}"
  secs="${out##* }"
  if [ "$code" = "$want" ]; then
    ms="$(awk -v s="${secs:-0}" 'BEGIN { printf "%d", s * 1000 }')"
    if [ -n "${EXPECT_BODY:-}" ] && ! grep -qF -- "$EXPECT_BODY" "$tmp"; then
      echo "FAIL  $url returned $code but the body does not contain: $EXPECT_BODY"
      exit 1
    fi
    if [ -n "${MAX_LATENCY_MS:-}" ] && [ "$ms" -gt "$MAX_LATENCY_MS" ]; then
      echo "FAIL  $url answered $code in ${ms}ms (limit ${MAX_LATENCY_MS}ms)"
      exit 1
    fi
    echo "PASS  $url -> $code in ${ms}ms (attempt $attempt/$retries)"
    exit 0
  fi
  echo "wait  attempt $attempt/$retries: got '${code:-no response}', want $want"
  sleep "$pause"
done

echo "FAIL  $url never returned $want after $retries attempts"
exit 1
