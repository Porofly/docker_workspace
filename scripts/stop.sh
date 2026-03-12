#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

COMPOSE_ARGS=("down")
if [ "${1:-}" = "--volumes" ]; then
    COMPOSE_ARGS+=("-v")
    echo "Stopping services and removing volumes..."
else
    echo "Stopping services..."
fi

docker compose -f "$PROJECT_ROOT/docker-compose.yml" "${COMPOSE_ARGS[@]}"

# X11 포워딩 복원
xhost -local:docker 2>/dev/null || true

echo "Done."
