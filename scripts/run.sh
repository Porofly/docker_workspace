#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

# X11 forwarding 허용
xhost +

CONTAINER_NAME="${PROJECT_NAME:-px4ros2-jazzy}"

if [ "${1:-}" = "--standalone" ]; then
    echo "Starting ${CONTAINER_NAME} (standalone)..."
    docker run -it \
        --name "${CONTAINER_NAME}" \
        --network host \
        --privileged \
        -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-0}" \
        -e DISPLAY="${DISPLAY:-:0}" \
        -e NVIDIA_VISIBLE_DEVICES=all \
        -e NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
        -v /dev:/dev \
        --gpus all \
        "${CONTAINER_NAME}:latest"
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
