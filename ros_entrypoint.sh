#!/bin/bash
set -e

# ROS2 Jazzy environment
source /opt/ros/jazzy/setup.bash

# px4_msgs workspace
if [ -f /root/ros2_ws/install/local_setup.bash ]; then
    source /root/ros2_ws/install/local_setup.bash
fi

exec "$@"
