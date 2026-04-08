#!/bin/bash
set -e

INSTANCE=${PX4_INSTANCE:-0}
PORT=${UXRCE_DDS_PORT:-8889}

echo "Starting MicroXRCEAgent on UDP port ${PORT}..."
MicroXRCEAgent udp4 -p ${PORT} &

echo "Starting PX4 SITL (instance ${INSTANCE})..."
cd /root/PX4-Autopilot
./build/px4_sitl_default/bin/px4 -i ${INSTANCE}
