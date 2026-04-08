#!/bin/bash
set -e

# ROS2 Jazzy 환경 (dustynv 소스빌드 + apt 패키지 경로)
source /opt/ros/jazzy/install/setup.bash
export AMENT_PREFIX_PATH=/opt/ros/jazzy:${AMENT_PREFIX_PATH}
export LD_LIBRARY_PATH=/opt/ros/jazzy/lib:${LD_LIBRARY_PATH}
export PATH=/opt/ros/jazzy/bin:${PATH}

# px4_msgs 워크스페이스
if [ -f /root/ros2_ws/install/local_setup.bash ]; then
    source /root/ros2_ws/install/local_setup.bash
fi

exec "$@"
