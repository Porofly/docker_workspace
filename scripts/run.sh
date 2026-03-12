#!/usr/bin/env bash
# set -euo pipefail

# PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# # .env 로드
# if [ -f "$PROJECT_ROOT/.env" ]; then
#     set -a; source "$PROJECT_ROOT/.env"; set +a
# fi

# IMAGE_NAME="${PROJECT_NAME:-myapp}"

# if [ "${1:-}" = "--standalone" ]; then
#     # 단일 컨테이너 모드
#     echo "Starting ${IMAGE_NAME} (standalone)..."
#     docker run -d \
#         --name "${IMAGE_NAME}-app" \
#         -p "${APP_PORT:-8080}:8080" \
#         "${IMAGE_NAME}:latest"
# else
#     # Docker Compose 모드
#     echo "Starting services with docker compose..."
#     docker compose -f "$PROJECT_ROOT/docker-compose.yml" \
#         --env-file "$PROJECT_ROOT/.env" up -d
# fi

# echo "Done."
