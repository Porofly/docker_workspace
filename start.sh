#!/bin/bash
set -e

echo "Starting PX4 SITL (uXRCE-DDS)..."
cd /root/PX4-Autopilot

# DRONE_ID를 PX4 인스턴스 번호로 직접 사용 (DRONE_ID=1 -> instance 1 -> /px4_1/fmu/...)
DRONE_ID=${DRONE_ID:-1}

# PX4_UXRCE_DDS_PORT: rcS 스크립트가 읽는 올바른 환경변수명
# 인스턴스별 포트 분리: DRONE_ID=1 -> 8889, DRONE_ID=2 -> 8890, ...
export PX4_UXRCE_DDS_PORT=$((8888 + DRONE_ID))

# PX4_UXRCE_DDS_NS: 토픽 네임스페이스를 명시적으로 지정
# rcS 자동 설정에 의존하지 않고 항상 px4_{DRONE_ID} 를 사용
export PX4_UXRCE_DDS_NS="px4_${DRONE_ID}"

echo "DRONE_ID=${DRONE_ID}, PX4_INSTANCE=${DRONE_ID}, PX4_UXRCE_DDS_PORT=${PX4_UXRCE_DDS_PORT}, PX4_UXRCE_DDS_NS=${PX4_UXRCE_DDS_NS}"

./build/px4_sitl_default/bin/px4 -i ${DRONE_ID}
