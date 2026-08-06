#!/usr/bin/env sh
set -eu

# Deploys a given image tag to the app directory on the VPS.
# Meant to run ON THE VPS (in the application directory, e.g. /opt/kps-tasks-api),
# with docker-compose.prod.yml and .env already present, alongside healthcheck.sh
# and rollback.sh (same directory).
#
# Required environment variables:
#   IMAGE_TAG          full image reference to deploy (e.g. ghcr.io/owner/kps-tasks-api:v1.0.0)
#   REGISTRY_URL        e.g. ghcr.io
#   REGISTRY_USER
#   REGISTRY_PASSWORD
#
# Optional:
#   APP_DIR             defaults to the current directory
#   HEALTH_RETRIES       defaults to 10
#   HEALTH_DELAY          defaults to 3 (seconds)

IMAGE_TAG=${IMAGE_TAG:?IMAGE_TAG is required}
REGISTRY_URL=${REGISTRY_URL:?REGISTRY_URL is required}
REGISTRY_USER=${REGISTRY_USER:?REGISTRY_USER is required}
REGISTRY_PASSWORD=${REGISTRY_PASSWORD:?REGISTRY_PASSWORD is required}

APP_DIR=${APP_DIR:-$(pwd)}
HEALTH_RETRIES=${HEALTH_RETRIES:-10}
HEALTH_DELAY=${HEALTH_DELAY:-3}

cd "$APP_DIR"

echo "==> Deploying $IMAGE_TAG in $APP_DIR"

if [ -f current-version.txt ]; then
  cp current-version.txt previous-version.txt
  echo "==> Previous version saved: $(cat previous-version.txt)"
else
  echo "==> No previous version on record (first deployment)"
fi

if grep -q '^IMAGE_TAG=' .env 2>/dev/null; then
  sed -i "s#^IMAGE_TAG=.*#IMAGE_TAG=$IMAGE_TAG#" .env
else
  echo "IMAGE_TAG=$IMAGE_TAG" >> .env
fi

echo "==> Logging in to $REGISTRY_URL"
echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_URL" -u "$REGISTRY_USER" --password-stdin

echo "==> Pulling new image"
docker compose -f docker-compose.prod.yml --env-file .env pull

echo "==> Restarting application"
docker compose -f docker-compose.prod.yml --env-file .env up -d

docker logout "$REGISTRY_URL" > /dev/null 2>&1 || true

APP_PORT=$(grep '^APP_PORT=' .env | cut -d= -f2)
export APP_PORT=${APP_PORT:-8000}
export HEALTH_RETRIES
export HEALTH_DELAY

SCRIPT_DIR=$(dirname "$0")

echo "==> Waiting for the application to respond on port $APP_PORT"
if "$SCRIPT_DIR/healthcheck.sh"; then
  echo "==> Deployment of $IMAGE_TAG successful"
  echo "$IMAGE_TAG" > current-version.txt
  exit 0
fi

echo "==> Healthcheck failed for $IMAGE_TAG, triggering automatic rollback" >&2
if REGISTRY_URL="$REGISTRY_URL" REGISTRY_USER="$REGISTRY_USER" REGISTRY_PASSWORD="$REGISTRY_PASSWORD" "$SCRIPT_DIR/rollback.sh"; then
  echo "==> Rollback executed successfully, previous version restored" >&2
else
  echo "==> Rollback ALSO FAILED — manual intervention required" >&2
fi

# The job must always fail here: the deployment of $IMAGE_TAG did not succeed,
# regardless of whether the rollback itself succeeded or not.
echo "==> Deployment of $IMAGE_TAG FAILED" >&2
exit 1
