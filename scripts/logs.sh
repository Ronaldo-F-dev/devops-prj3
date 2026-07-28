#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
cd "$PROJECT_ROOT"

DOCKER_COMPOSE=${DOCKER_COMPOSE:-"docker compose"}
SERVICE=${1:-app}

eval "$DOCKER_COMPOSE logs -f $SERVICE"