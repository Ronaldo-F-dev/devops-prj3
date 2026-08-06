#!/usr/bin/env sh
set -eu

# Restores the last known-good image, recorded in previous-version.txt by deploy.sh.
# Meant to run ON THE VPS, in the application directory (e.g. /opt/kps-tasks-api),
# normally invoked by deploy.sh when a fresh deployment fails its healthcheck.
#
# Required environment variables:
#   REGISTRY_URL, REGISTRY_USER, REGISTRY_PASSWORD
#
# Optional:
#   APP_DIR (defaults to current directory)

REGISTRY_URL=${REGISTRY_URL:?REGISTRY_URL is required}
REGISTRY_USER=${REGISTRY_USER:?REGISTRY_USER is required}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:?REGISTRY_PASSWORD is required}

APP_DIR=${APP_DIR:-$(pwd)}
cd "$APP_DIR"

if [ ! -f previous-version.txt ]; then
  echo "==> No previous-version.txt found, nothing to roll back to" >&2
  exit 1
fi

PREVIOUS_TAG=$(cat previous-version.txt)
echo "==> Rolling back to $PREVIOUS_TAG"

if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
  sed -i "s#^IMAGE_TAG=.*#IMAGE_TAG=$PREVIOUS_TAG#" .env
else
  echo "IMAGE_TAG=$PREVIOUS_TAG" >> .env
fi

echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin
docker compose -f docker-compose.prod.yml --env-file .env pull
docker compose -f docker-compose.prod.yml --env-file .env up -d
docker logout "$REGISTRY_URL" > /dev/null 2>&1 || true

echo "==> Verifying the rolled-back version responds"
if "$(dirname "$0")/healthcheck.sh"; then
  echo "==> Rollback successful: $PREVIOUS_TAG is back online"
  echo "$PREVIOUS_TAG" > current-version.txt
  exit 0
fi

echo "==> Rollback FAILED: $PREVIOUS_TAG does not respond either — manual intervention required" >&2
exit 1
