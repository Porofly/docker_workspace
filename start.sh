#!/bin/bash
set -e

# 인자 우선, 없으면 환경변수, 기본값 0
INSTANCE=${1:-${PX4_INSTANCE:-0}}

echo "Starting PX4 SITL Zenoh (instance ${INSTANCE})..."
cd /root/PX4-Autopilot

# extras 스크립트로 ZENOH_ENABLE 자동 설정
EXTRAS_DIR=build/px4_sitl_zenoh/rootfs/etc/init.d-posix
mkdir -p ${EXTRAS_DIR}
echo "param set ZENOH_ENABLE 1" > ${EXTRAS_DIR}/rc.autostart_extras

./build/px4_sitl_zenoh/bin/px4 -i ${INSTANCE}
