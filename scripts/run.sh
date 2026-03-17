#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

# X11 포워딩 허용
echo "Allowing X11 forwarding for Docker..."
xhost +local:docker 2>/dev/null || echo "Warning: xhost not available, GUI may not work"

# 현재 호스트의 DISPLAY를 .env에 자동 반영
if [ -n "$DISPLAY" ]; then
    sed -i "s/^DISPLAY=.*/DISPLAY=$DISPLAY/" "$PROJECT_ROOT/.env"
    echo "DISPLAY set to $DISPLAY"
fi

CONTAINER_NAME="${PROJECT_NAME:-px4-ros2-dev}"

# 컨테이너가 이미 존재하면 start, 없으면 up으로 생성
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "Starting existing container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" start
else
    echo "Creating and starting container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" \
        --env-file "$PROJECT_ROOT/.env" up -d
fi

echo "Done. Container is running."
echo "Attach with: docker exec -it ${CONTAINER_NAME} bash"
