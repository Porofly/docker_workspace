# ============================================
# ROS2 Jazzy + px4_msgs on Jetson Orin Nano
# dustynv/ros (L4T r36.4.0 + Ubuntu 24.04 + CUDA 12.8 + ROS2 Jazzy)
# ============================================

FROM dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04

LABEL maintainer="kyg"
LABEL description="ROS2 Jazzy + px4_msgs on Jetson Orin Nano"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

SHELL ["/bin/bash", "-c"]

# ============================================
# 1. ROS GPG 키 갱신 (베이스 이미지의 만료된 키 교체)
# ============================================
RUN rm -f /usr/share/keyrings/ros-archive-keyring.gpg \
    && curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg

# ============================================
# 2. Locale + 시스템 패키지 + ROS2 dev-tools + RMW (zenoh)
#    (ros-jazzy-ros-base는 베이스 이미지에 포함)
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales \
        curl \
        wget \
        git \
        build-essential \
        cmake \
        python3-pip \
        python3-dev \
        sudo \
        vim \
        nano \
        tmux \
        ros-dev-tools \
        ros-jazzy-rmw-zenoh-cpp \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. px4_msgs ROS2 워크스페이스
# ============================================
RUN mkdir -p /root/ros2_ws/src \
    && cd /root/ros2_ws/src \
    && git clone -b release/1.17 https://github.com/PX4/px4_msgs.git
RUN source /opt/ros/jazzy/install/setup.bash \
    && cd /root/ros2_ws && colcon build

# ============================================
# 4. 환경 설정
# ============================================
RUN echo "source /opt/ros/jazzy/install/setup.bash" >> /root/.bashrc \
    && echo "export AMENT_PREFIX_PATH=/opt/ros/jazzy:\${AMENT_PREFIX_PATH}" >> /root/.bashrc \
    && echo "export LD_LIBRARY_PATH=/opt/ros/jazzy/lib:\${LD_LIBRARY_PATH}" >> /root/.bashrc \
    && echo "export PATH=/opt/ros/jazzy/bin:\${PATH}" >> /root/.bashrc \
    && echo "source /root/ros2_ws/install/local_setup.bash" >> /root/.bashrc \
    && echo "export ROS_DOMAIN_ID=0" >> /root/.bashrc \
    && echo "export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /root/.bashrc

COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
