# ============================================
# PX4 + ROS2 Kilted on Jetson Orin Nano
# L4T JetPack r36.4.0 (ARM64)
# ============================================

FROM nvcr.io/nvidia/l4t-jetpack:r36.4.0

LABEL maintainer="kyg"
LABEL description="PX4 + ROS2 Kilted development environment on Jetson Orin Nano"

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
        tshark \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. ROS2 Kilted 설치
# ============================================
RUN curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.key \
        -o /usr/share/keyrings/ros-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/ros-archive-keyring.gpg] \
        http://packages.ros.org/ros2/ubuntu $(. /etc/os-release && echo $UBUNTU_CODENAME) main" \
        | tee /etc/apt/sources.list.d/ros2.list > /dev/null \
    && apt-get update && apt-get install -y \
        ros-kilted-ros-base \
        ros-dev-tools \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. RMW 구현체 (성능 비교용 3종)
# ============================================
RUN apt-get update && apt-get install -y \
        ros-kilted-rmw-fastrtps-cpp \
        ros-kilted-rmw-cyclonedds-cpp \
        ros-kilted-rmw-zenoh-cpp \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 4. Micro XRCE-DDS Agent v2.4.3
# ============================================
RUN cd /tmp \
    && git clone -b v2.4.3 https://github.com/eProsima/Micro-XRCE-DDS-Agent.git \
    && cd Micro-XRCE-DDS-Agent && mkdir build && cd build \
    && cmake .. && make -j$(nproc) && make install \
    && ldconfig /usr/local/lib/ \
    && rm -rf /tmp/Micro-XRCE-DDS-Agent

# ============================================
# 5. PX4-Autopilot v1.17.0-rc2 (SITL)
# ============================================
RUN git clone -b v1.17.0-rc2 --recursive \
        https://github.com/PX4/PX4-Autopilot.git /root/PX4-Autopilot \
    && cd /root/PX4-Autopilot \
    && bash Tools/setup/ubuntu.sh --no-nuttx \
    && make px4_sitl_default \
    && make px4_sitl_zenoh

# ============================================
# 6. px4_msgs ROS2 워크스페이스
# ============================================
RUN mkdir -p /root/ros2_ws/src \
    && cd /root/ros2_ws/src \
    && git clone -b release/1.17 https://github.com/PX4/px4_msgs.git
RUN source /opt/ros/kilted/setup.bash \
    && cd /root/ros2_ws && colcon build

# ============================================
# 7. 환경 설정
# ============================================
RUN echo "source /opt/ros/kilted/setup.bash" >> /root/.bashrc \
    && echo "source /root/ros2_ws/install/local_setup.bash" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# === ROS2 설정 ===" >> /root/.bashrc \
    && echo "export ROS_DOMAIN_ID=0" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# RMW 성능 비교: 아래 중 하나를 주석 해제하여 사용" >> /root/.bashrc \
    && echo "export RMW_IMPLEMENTATION=rmw_fastrtps_cpp" >> /root/.bashrc \
    && echo "# export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp" >> /root/.bashrc \
    && echo "# export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# === PX4 설정 ===" >> /root/.bashrc \
    && echo "export PX4_INSTANCE=0" >> /root/.bashrc \
    && echo "export UXRCE_DDS_PORT=8889" >> /root/.bashrc

COPY ros_entrypoint.sh /ros_entrypoint.sh
COPY start.sh /root/start.sh
RUN chmod +x /ros_entrypoint.sh /root/start.sh
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
