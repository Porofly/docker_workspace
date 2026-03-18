#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
CONTAINER_NAME=$(grep 'container_name:' "$COMPOSE_FILE" | awk '{print $2}')
IMAGE_NAME="${PROJECT_NAME:-uwb-recon}"

# X11 디스플레이 접근 허용 (GUI 앱용)
xhost + 2>/dev/null || true

if [ "${1:-}" = "--standalone" ]; then
    # 단일 컨테이너 모드
    echo "Starting ${IMAGE_NAME} (standalone)..."
    docker run -it \
        --name "${IMAGE_NAME}" \
        --network host \
        --privileged \
        -e ROS_DOMAIN_ID=0 \
        -e DISPLAY="${DISPLAY:-}" \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
        -v /dev:/dev \
        "${IMAGE_NAME}:latest"
else
    # Docker Compose 모드: 중지된 컨테이너가 있으면 start, 없으면 up
    if docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" ps -a --format json 2>/dev/null | grep -q "$CONTAINER_NAME"; then
        echo "Resuming existing container..."
        docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" start
    else
        echo "Creating and starting services..."
        docker compose -f "$COMPOSE_FILE" -p "$CONTAINER_NAME" up -d
    fi
    echo "Attaching to $CONTAINER_NAME..."
    docker exec -it "$CONTAINER_NAME" bash
fi

echo "Done."
