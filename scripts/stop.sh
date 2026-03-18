#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

IMAGE_NAME="${PROJECT_NAME:-uwb-recon}"

if [ "${1:-}" = "--standalone" ]; then
    # 단일 컨테이너 중지 (삭제하지 않음)
    echo "Stopping ${IMAGE_NAME}..."
    docker stop "${IMAGE_NAME}"
elif [ "${1:-}" = "--down" ]; then
    # 컨테이너 완전 삭제
    echo "Removing services (data will be lost)..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" down
elif [ "${1:-}" = "--down-volumes" ]; then
    # 컨테이너 + 볼륨 완전 삭제
    echo "Removing services and volumes..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" down -v
else
    # 기본: stop (컨테이너 유지, 데이터 보존)
    echo "Stopping services (container preserved)..."
    docker compose -f "$PROJECT_ROOT/docker-compose.yml" stop
fi

echo "Done."
