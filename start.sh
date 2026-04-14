#!/bin/bash
set -e

echo "Starting PX4 SITL (uXRCE-DDS)..."
cd /root/PX4-Autopilot

# DRONE_ID를 PX4 인스턴스 번호로 직접 사용 (DRONE_ID=1 -> instance 1 -> /px4_1/fmu/...)
DRONE_ID=${DRONE_ID:-1}

# uXRCE-DDS 에이전트 연결 설정
# 인스턴스별로 포트를 분리: 8889, 8890, 8891, ...
export UXRCE_DDS_AG_IP=2130706433          # 127.0.0.1 (int32)
export UXRCE_DDS_PRT=$((8888 + DRONE_ID))

echo "DRONE_ID=${DRONE_ID}, PX4_INSTANCE=${DRONE_ID}, UXRCE_DDS_PRT=${UXRCE_DDS_PRT}"

./build/px4_sitl_default/bin/px4 -i ${DRONE_ID}
