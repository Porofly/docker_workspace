#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# .env 로드
if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a; source "$PROJECT_ROOT/.env"; set +a
fi

IMAGE_NAME="${PROJECT_NAME:-px4ros2-jetson}"
IMAGE_TAG="${1:-latest}"

echo "Building ${IMAGE_NAME}:${IMAGE_TAG} for linux/arm64..."

# QEMU 에뮬레이션 설정 (최초 1회)
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes 2>/dev/null || true

# buildx로 ARM64 크로스 빌드
docker buildx create --name jetson-builder --use 2>/dev/null || docker buildx use jetson-builder
docker buildx build \
    --platform linux/arm64 \
    -t "${IMAGE_NAME}:${IMAGE_TAG}" \
    --load \
    "$PROJECT_ROOT"

echo "Done: ${IMAGE_NAME}:${IMAGE_TAG}"
echo "Push to registry: docker tag ${IMAGE_NAME}:${IMAGE_TAG} <REGISTRY>/${IMAGE_NAME}:${IMAGE_TAG} && docker push <REGISTRY>/${IMAGE_NAME}:${IMAGE_TAG}"
