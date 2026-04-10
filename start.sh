#!/bin/bash
set -e

echo "Starting PX4 SITL Zenoh..."
cd /root/PX4-Autopilot

# rcS 패치: ZENOH_ENABLE 조건 체크를 제거하고 zenoh를 항상 시작
RCS=build/px4_sitl_zenoh/etc/init.d-posix/rcS
if ! grep -q "# ZENOH_AUTO_START_PATCHED" "$RCS"; then
    sed -i 's|if param greater -s ZENOH_ENABLE 0|# ZENOH_AUTO_START_PATCHED\nif true|' "$RCS"
    echo "rcS patched for automatic zenoh start"
fi

./build/px4_sitl_zenoh/bin/px4
