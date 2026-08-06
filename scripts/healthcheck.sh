#!/usr/bin/env sh
set -eu

# Polls GET /health until it succeeds or the retry budget is exhausted.
# Exit code 0 = healthy, 1 = never became healthy.
#
# Usage: healthcheck.sh [port] [retries] [delay_seconds]
# Or via environment: APP_PORT, HEALTH_RETRIES, HEALTH_DELAY

PORT=${1:-${APP_PORT:-8000}}
RETRIES=${2:-${HEALTH_RETRIES:-10}}
DELAY=${3:-${HEALTH_DELAY:-3}}

i=1
while [ "$i" -le "$RETRIES" ]; do
  if curl -fsS "http://127.0.0.1:${PORT}/health" > /dev/null 2>&1; then
    echo "==> Healthcheck OK (attempt $i/$RETRIES)"
    exit 0
  fi
  echo "==> Healthcheck attempt $i/$RETRIES failed, waiting ${DELAY}s"
  i=$((i + 1))
  sleep "$DELAY"
done

echo "==> Healthcheck failed after $RETRIES attempts" >&2
exit 1
