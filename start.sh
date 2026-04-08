#!/bin/bash
set -e

INSTANCE=${PX4_INSTANCE:-0}

echo "Starting PX4 SITL (instance ${INSTANCE})..."
cd /root/PX4-Autopilot
./build/px4_sitl_zenoh/bin/px4 -i ${INSTANCE}
