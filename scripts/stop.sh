#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

# 기본: stop (컨테이너 유지), --rm: down (컨테이너 삭제)
if [ "${1:-}" = "--rm" ]; then
    echo "Stopping and removing container..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" down
else
    echo "Stopping container (data preserved)..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" stop
fi

# X11 포워딩 복원
xhost - 2>/dev/null || true

echo "Done."
