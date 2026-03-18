# ============================================
# PX4 + ROS2 Humble + Gazebo Classic + YOLOv8
# Docker Development Environment
# ============================================

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

LABEL maintainer="kyg"
LABEL description="PX4 ROS2 Humble Gazebo Classic YOLOv8 development environment"

SHELL ["/bin/bash", "-c"]

# ============================================
# 1. 시스템 기본 패키지 + 로케일 설정
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    locales \
    curl \
    wget \
    git \
    cmake \
    build-essential \
    python3-pip \
    python3-dev \
    lsb-release \
    gnupg2 \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    sudo \
    vim \
    nano \
    tmux \
    bmon \
    tcpdump \
    wireshark-common \
    tshark \
    gstreamer1.0-plugins-bad \
    gstreamer1.0-plugins-base \
    gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-ugly \
    gstreamer1.0-libav \
    libgstreamer-plugins-base1.0-dev \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. ROS2 Humble 설치
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    software-properties-common \
    && add-apt-repository universe \
    && export ROS_APT_SOURCE_VERSION=$(curl -s https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest | grep -F "tag_name" | awk -F\" '{print $4}') \
    && curl -L -o /tmp/ros2-apt-source.deb \
       "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.jammy_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && rm /tmp/ros2-apt-source.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       ros-humble-desktop \
       ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. rmw_zenoh 설치
# ============================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ros-humble-rmw-zenoh-cpp \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 4. PX4-Autopilot 클론
# ============================================
WORKDIR /root
RUN git clone https://github.com/PX4/PX4-Autopilot.git --recursive

# ============================================
# 5. Micro XRCE-DDS Agent 빌드
# ============================================
WORKDIR /root
RUN git clone -b v2.4.3 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git \
    && cd Micro-XRCE-DDS-Agent \
    && mkdir build && cd build \
    && cmake .. \
    && make -j$(nproc) \
    && make install \
    && ldconfig /usr/local/lib/ \
    && cd /root \
    && rm -rf Micro-XRCE-DDS-Agent

# ============================================
# 6. YOLOv8 설치 (CUDA 11.8 기반)
# ============================================
RUN pip3 install --no-cache-dir \
    torch torchvision --index-url https://download.pytorch.org/whl/cu118 \
    && pip3 install --no-cache-dir ultralytics

# ============================================
# 7. 환경 설정
# ============================================
RUN echo "" >> /root/.bashrc \
    && echo "# ROS2 Humble" >> /root/.bashrc \
    && echo "source /opt/ros/humble/setup.bash" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# RMW Zenoh" >> /root/.bashrc \
    && echo "# export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# RMW FastDDS" >> /root/.bashrc \
    && echo "# export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" >> /root/.bashrc \
    && echo "" >> /root/.bashrc

WORKDIR /root/ros2_ws

CMD ["bash"]
