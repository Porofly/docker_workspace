# ============================================
# PX4 + ROS2 Jazzy on Jetson Orin Nano
# dustynv/ros (L4T r36.4.0 + Ubuntu 24.04 + CUDA 12.8 + ROS2 Jazzy)
# ============================================

FROM dustynv/ros:jazzy-ros-base-r36.4.0-cu128-24.04

LABEL maintainer="kyg"
LABEL description="PX4 + ROS2 Jazzy development environment on Jetson Orin Nano"

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
RUN echo 'wireshark-common wireshark-common/install-setuid boolean false' | debconf-set-selections \
    && apt-get update && apt-get install -y --no-install-recommends \
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
        ros-dev-tools \
        ros-jazzy-rmw-zenoh-cpp \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 3. PX4-Autopilot v1.17.0-rc2 (SITL)
# ============================================
RUN pip config set global.index-url https://pypi.org/simple/ \
    && pip config unset global.extra-index-url 2>/dev/null || true \
    && git clone -b v1.17.0-rc2 --recursive \
        https://github.com/PX4/PX4-Autopilot.git /root/PX4-Autopilot \
    && cd /root/PX4-Autopilot \
    && bash Tools/setup/ubuntu.sh --no-nuttx \
    && make px4_sitl_zenoh

# ============================================
# 4. px4_msgs ROS2 워크스페이스
# ============================================
RUN mkdir -p /root/ros2_ws/src \
    && cd /root/ros2_ws/src \
    && git clone -b release/1.17 https://github.com/PX4/px4_msgs.git
RUN source /opt/ros/jazzy/setup.bash \
    && cd /root/ros2_ws && colcon build

# ============================================
# 5. 환경 설정
# ============================================
RUN echo "source /opt/ros/jazzy/setup.bash" >> /root/.bashrc \
    && echo "source /root/ros2_ws/install/local_setup.bash" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# === ROS2 설정 ===" >> /root/.bashrc \
    && echo "export ROS_DOMAIN_ID=0" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "export RMW_IMPLEMENTATION=rmw_zenoh_cpp" >> /root/.bashrc \
    && echo "" >> /root/.bashrc \
    && echo "# === PX4 설정 ===" >> /root/.bashrc \
    && echo "export PX4_INSTANCE=0" >> /root/.bashrc

COPY ros_entrypoint.sh /ros_entrypoint.sh
COPY start.sh /root/start.sh
RUN chmod +x /ros_entrypoint.sh /root/start.sh
ENTRYPOINT ["/ros_entrypoint.sh"]
CMD ["bash"]
