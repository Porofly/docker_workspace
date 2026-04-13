# ============================================
# ROS2 Jazzy + px4_msgs on Jetson Orin Nano
# dustynv/cuda (L4T r36.4.0 + Ubuntu 24.04 + CUDA 12.8)
# + ROS2 Jazzy apt 설치 (uXRCE-DDS)
# ============================================

FROM dustynv/cuda:12.8-samples-r36.4.0-cu128-24.04

LABEL maintainer="kyg"
LABEL description="ROS2 Jazzy + px4_msgs on Jetson Orin Nano"

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

SHELL ["/bin/bash", "-c"]

# ============================================
# 1. Locale + 시스템 기본 패키지
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
        gnupg2 \
        lsb-release \
        software-properties-common \
        ca-certificates \
        sudo \
        vim \
        nano \
        tmux \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. ROS2 Jazzy 설치 (apt)
# ============================================
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
        http://packages.ros.org/ros2/ubuntu $(lsb_release -cs) main" \
        | tee /etc/apt/sources.list.d/ros2.list > /dev/null \
    && apt-get update && apt-get install -y \
        ros-jazzy-ros-base \
        ros-dev-tools \
        ros-jazzy-rmw-fastrtps-cpp \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. px4_msgs + swarm_bridge ROS2 워크스페이스
# ============================================
RUN mkdir -p /root/ros2_ws/src \
    && cd /root/ros2_ws/src \
    && git clone -b release/1.17 https://github.com/PX4/px4_msgs.git
COPY ros2_ws/src/swarm_bridge /root/ros2_ws/src/swarm_bridge
RUN source /opt/ros/jazzy/setup.bash \
    && cd /root/ros2_ws && colcon build

# ============================================
# 3-b. Micro XRCE-DDS Agent (eProsima standalone)
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
        libssl-dev \
        libasio-dev \
        libtinyxml2-dev \
    && rm -rf /var/lib/apt/lists/* \
    && git clone https://github.com/eProsima/Micro-XRCE-DDS-Agent.git /tmp/uxrce-agent \
    && cd /tmp/uxrce-agent \
    && mkdir build && cd build \
    && cmake .. \
    && make -j$(nproc) \
    && make install \
    && ldconfig \
    && rm -rf /tmp/uxrce-agent

# ============================================
# 4. 환경 설정 (uXRCE-DDS)
# ============================================
RUN echo "source /opt/ros/jazzy/setup.bash" >> /root/.bashrc \
    && echo "source /root/ros2_ws/install/local_setup.bash" >> /root/.bashrc \
    && echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" >> /root/.bashrc

COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
