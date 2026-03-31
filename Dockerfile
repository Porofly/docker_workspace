# ============================================
# PX4 + ROS2 Jazzy Development Environment
# Ubuntu 24.04 (Noble)
# ============================================

FROM ubuntu:24.04

LABEL maintainer="kyg"
LABEL description="PX4 + ROS2 Jazzy development environment on Ubuntu 24.04"

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
        bmon \
        tcpdump \
        wireshark-common \
        tshark \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# NVIDIA GPU 환경변수
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=graphics,utility,compute

# ============================================
# 2. ROS2 Jazzy 설치
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
        ros-jazzy-desktop \
        ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. Micro XRCE-DDS Agent 빌드
# ============================================
RUN cd /tmp \
    && git clone -b v2.4.3 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git \
    && cd Micro-XRCE-DDS-Agent \
    && mkdir build && cd build \
    && cmake .. \
    && make -j$(nproc) \
    && make install \
    && ldconfig /usr/local/lib/ \
    && cd /tmp && rm -rf Micro-XRCE-DDS-Agent

# ============================================
# 4. PX4-Autopilot
# ============================================
WORKDIR /root
RUN git clone https://github.com/PX4/PX4-Autopilot.git --recursive

# ============================================
# 5. 환경 설정
# ============================================
RUN echo "" >> /root/.bashrc \
    && echo "# ROS2 Jazzy" >> /root/.bashrc \
    && echo "source /opt/ros/jazzy/setup.bash" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# RMW (default: FastDDS, uncomment for Zenoh)" >> /root/.bashrc \
    && echo "# export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /root/.bashrc \
    && echo "" >> /root/.bashrc

# ============================================
# 6. Entrypoint
# ============================================
COPY ros_entrypoint.sh /ros_entrypoint.sh
RUN chmod +x /ros_entrypoint.sh

WORKDIR /root
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
