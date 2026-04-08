#!/bin/bash
set -e

# ROS2 Jazzy 환경
source /opt/ros/jazzy/setup.bash

# px4_msgs 워크스페이스
if [ -f /root/ros2_ws/install/local_setup.bash ]; then
    source /root/ros2_ws/install/local_setup.bash
fi

exec "$@"
