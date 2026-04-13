#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

IMAGE_NAME="${PROJECT_NAME:-px4ros2-jetson-dds}"
IMAGE_TAG="${1:-latest}"

echo "=== Building PX4 image ==="
docker build -t "${IMAGE_NAME}-px4:${IMAGE_TAG}" -f "$PROJECT_ROOT/px4/Dockerfile" "$PROJECT_ROOT"
echo "Done: ${IMAGE_NAME}-px4:${IMAGE_TAG}"

echo ""
echo "=== Building ROS2 image ==="
docker build -t "${IMAGE_NAME}-ros2:${IMAGE_TAG}" -f "$PROJECT_ROOT/ros2/Dockerfile" "$PROJECT_ROOT"
echo "Done: ${IMAGE_NAME}-ros2:${IMAGE_TAG}"
