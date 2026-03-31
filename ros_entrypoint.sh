#!/bin/bash
set -e

# ROS2 Jazzy environment
source /opt/ros/jazzy/setup.bash

exec "$@"
