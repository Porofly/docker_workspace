#!/bin/bash
set -e

# 인자 우선, 없으면 환경변수, 기본값 0
INSTANCE=${1:-${PX4_INSTANCE:-0}}

echo "Starting PX4 SITL Zenoh (instance ${INSTANCE})..."
cd /root/PX4-Autopilot

# ZENOH_ENABLE 파라미터를 자동 설정하는 startup 명령
./build/px4_sitl_zenoh/bin/px4 -i ${INSTANCE} -c "param set ZENOH_ENABLE 1"
