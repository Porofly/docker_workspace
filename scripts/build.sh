#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

IMAGE_NAME="${PROJECT_NAME:-px4ros2-jetson}"
IMAGE_TAG="${1:-latest}"

echo "Building ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" "$PROJECT_ROOT"
echo "Done: ${IMAGE_NAME}:${IMAGE_TAG}"
