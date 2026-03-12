#!/usr/bin/env bash
# set -euo pipefail

# PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# # .env 로드
# if [ -f "$PROJECT_ROOT/.env" ]; then
#     set -a; source "$PROJECT_ROOT/.env"; set +a
# fi

# IMAGE_NAME="${PROJECT_NAME:-myapp}"

# if [ "${1:-}" = "--standalone" ]; then
#     # 단일 컨테이너 중지
#     echo "Stopping ${IMAGE_NAME}-app..."
#     docker stop "${IMAGE_NAME}-app" && docker rm "${IMAGE_NAME}-app"
# else
#     # Docker Compose 중지
#     COMPOSE_ARGS=("down")
#     if [ "${1:-}" = "--volumes" ]; then
#         COMPOSE_ARGS+=("-v")
#         echo "Stopping services and removing volumes..."
#     else
#         echo "Stopping services..."
#     fi
#     docker compose -f "$PROJECT_ROOT/docker-compose.yml" "${COMPOSE_ARGS[@]}"
# fi

# echo "Done."
