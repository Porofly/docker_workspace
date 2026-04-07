#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

CONTAINER_NAME="${CONTAINER_NAME:-px4ros2-jetson}"

if [ "${1:-}" = "--standalone" ]; then
    echo "Starting ${CONTAINER_NAME} (standalone)..."
    docker run -it \
        --name "${CONTAINER_NAME}" \
        --network host \
        --privileged \
        --runtime nvidia \
        -v /tmp:/tmp \
        -v /dev:/dev \
        "${PROJECT_NAME:-px4ros2-jetson}:latest"
else
    # Docker Compose 모드
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo "Starting existing container..."
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" start
    else
        echo "Creating and starting container..."
        docker compose -f "$PROJECT_ROOT/docker-compose.yml" \
            --env-file "$PROJECT_ROOT/.env" up -d
    fi
    echo "Attach: docker exec -it ${CONTAINER_NAME} bash"
fi
