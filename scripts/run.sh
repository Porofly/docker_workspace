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

echo "Starting services with docker compose..."
docker compose -f "$PROJECT_ROOT/docker-compose.yml" \
    --env-file "$PROJECT_ROOT/.env" up -d

echo "Done. Container is running."
echo "Attach with: docker exec -it ${PROJECT_NAME:-px4-ros2-dev} bash"
