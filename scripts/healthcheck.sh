#!/usr/bin/env sh
set -eu

URL=${1:-${HEALTHCHECK_URL:-http://127.0.0.1:8000/health}}

curl --fail --silent --show-error "$URL" >/dev/null
printf 'healthcheck ok: %s\n' "$URL"