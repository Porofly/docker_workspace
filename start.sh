#!/bin/bash
set -e

echo "Starting PX4 SITL (uXRCE-DDS)..."
cd /root/PX4-Autopilot

# uXRCE-DDS 에이전트 연결 설정 (기본값: localhost:8888 UDP)
# 두 컨테이너 모두 network_mode: host이므로 로컬호스트로 통신
export UXRCE_DDS_AG_IP=2130706433   # 127.0.0.1 (int32)
export UXRCE_DDS_PRT=8888

./build/px4_sitl_default/bin/px4
