# ============================================
# PX4-Autopilot v1.17.0-rc2 SITL (Zenoh)
# Ubuntu 22.04 (Jammy) ARM64
# ============================================

FROM arm64v8/ubuntu:22.04

LABEL maintainer="kyg"
LABEL description="PX4 SITL Zenoh on Jetson Orin Nano"

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
        lsb-release \
        sudo \
        vim \
        nano \
        tmux \
    && locale-gen en_US en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

# ============================================
# 2. PX4-Autopilot v1.17.0-rc2 (SITL Zenoh)
# ============================================
RUN git clone -b v1.17.0-rc2 --recursive \
        https://github.com/PX4/PX4-Autopilot.git /root/PX4-Autopilot \
    && cd /root/PX4-Autopilot \
    && bash Tools/setup/ubuntu.sh --no-nuttx \
    && make px4_sitl_zenoh

# ============================================
# 3. 환경 설정
# ============================================
RUN echo "export PX4_INSTANCE=0" >> /root/.bashrc

COPY start.sh /root/start.sh
RUN chmod +x /root/start.sh
CMD ["bash"]
