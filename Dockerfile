# ============================================
# UWB Recon Docker Workspace
# ============================================
# Ubuntu 22.04 + ROS2 Humble + uXRCE-DDS Agent
# + PX4-Autopilot (SITL) + px4_msgs

FROM ubuntu:22.04

LABEL maintainer="kyg"
LABEL description="UWB Recon system with ROS2 Humble, PX4 SITL, uXRCE-DDS Agent"

ENV DEBIAN_FRONTEND=noninteractive

# ============================================
# 1. Locale & 기본 패키지
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
        locales \
        curl \
        wget \
        git \
        build-essential \
        cmake \
        python3-pip \
        gnupg2 \
        lsb-release \
        software-properties-common \
        ca-certificates \
        sudo \
        vim \
        nano \
        bmon \
        tcpdump \
        wireshark-common \
        tshark \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

# NVIDIA GPU 컨테이너 설정 (Gazebo GUI 렌더링용)
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute

# ============================================
# 2. ROS2 Humble 설치 (최신 공식 방법: ros2-apt-source .deb)
# ============================================
RUN apt-get update && apt-get install -y curl \
    && export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F'"' '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb \
        "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && rm /tmp/ros2-apt-source.deb \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        ros-humble-desktop \
        ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# ROS2 환경 설정
RUN echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc

# ============================================
# 3. Micro XRCE-DDS Agent 빌드 및 설치
# ============================================
RUN cd /tmp \
    && git clone https://github.com/eProsima/Micro-XRCE-DDS-Agent.git \
    && cd Micro-XRCE-DDS-Agent \
    && mkdir build && cd build \
    && cmake .. \
    && make -j$(nproc) \
    && make install \
    && ldconfig /usr/local/lib/ \
    && cd /tmp && rm -rf Micro-XRCE-DDS-Agent

# ============================================
# 4. PX4-Autopilot (main, SITL only)
# ============================================
WORKDIR /root
RUN git clone https://github.com/PX4/PX4-Autopilot.git --recursive

# ============================================
# 5. px4_msgs 워크스페이스
# ============================================
RUN mkdir -p /root/ros2_ws/src \
    && cd /root/ros2_ws/src \
    && git clone https://github.com/PX4/px4_msgs.git

RUN /bin/bash -c "source /opt/ros/humble/setup.bash \
    && cd /root/ros2_ws \
    && colcon build"

# ============================================
# 6. Entrypoint
# ============================================
COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

WORKDIR /root

ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
