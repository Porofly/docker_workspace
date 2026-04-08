#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

CONTAINER_NAME="${CONTAINER_NAME:-px4ros2-jetson}"

if [ "${1:-}" = "--standalone" ]; then
    echo "Stopping ${CONTAINER_NAME}..."
    docker stop "${CONTAINER_NAME}"
elif [ "${1:-}" = "--rm" ]; then
    echo "Removing container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" down
elif [ "${1:-}" = "--rm-volumes" ]; then
    echo "Removing container and volumes..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v
else
    echo "Stopping container (preserved)..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" stop
fi

echo "Done."
