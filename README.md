# PX4 + ROS2 Jazzy Docker Workspace

Ubuntu 24.04 기반 PX4-Autopilot + ROS2 Jazzy 개발 환경.

## 포함 구성요소

- **Ubuntu 24.04** (Noble)
- **ROS2 Jazzy** Desktop
- **PX4-Autopilot** (recursive clone, `/root/PX4-Autopilot`)
- **Micro XRCE-DDS Agent** v2.4.3 (PX4 ↔ ROS2 브릿지)
- NVIDIA GPU 지원 + X11 GUI 포워딩
- 네트워크 디버깅 도구 (bmon, tcpdump, tshark)

## Quick Start

```bash
# 1. 환경변수 설정
cp .env.example .env

# 2. 이미지 빌드
bash scripts/build.sh

# 3. 컨테이너 실행
bash scripts/run.sh

# 4. 컨테이너 접속
docker exec -it px4ros2-jazzy bash
```

## 스크립트 사용법

| 스크립트 | 설명 |
|----------|------|
| `scripts/build.sh [태그]` | Docker 이미지 빌드 (기본 태그: `latest`) |
| `scripts/run.sh` | Docker Compose로 컨테이너 시작 |
| `scripts/run.sh --standalone` | 단일 컨테이너 모드 (interactive) |
| `scripts/stop.sh` | 컨테이너 중지 (보존) |
| `scripts/stop.sh --rm` | 컨테이너 중지 및 삭제 |
| `scripts/stop.sh --rm-volumes` | 컨테이너 + 볼륨 삭제 |
| `scripts/stop.sh --standalone` | standalone 컨테이너 중지 |

## 컨테이너 내 주요 경로

| 경로 | 설명 |
|------|------|
| `/root/PX4-Autopilot` | PX4 소스 코드 |
| `/opt/ros/jazzy/` | ROS2 Jazzy 설치 경로 |

## 주요 워크플로우

### PX4 SITL 시뮬레이션
```bash
cd /root/PX4-Autopilot
make px4_sitl gz_x500
```

### Micro XRCE-DDS Agent 실행
```bash
MicroXRCEAgent udp4 -p 8888
```

### ROS2 토픽 확인
```bash
ros2 topic list
```

### px4_msgs 수동 설치 (필요 시)
```bash
mkdir -p ~/ros2_ws/src
cd ~/ros2_ws/src
git clone https://github.com/PX4/px4_msgs.git
cd ~/ros2_ws
colcon build
source install/local_setup.bash
```

## RMW 변경 (선택)

기본 RMW는 FastDDS. Zenoh 사용 시:
```bash
# ~/.bashrc에서 주석 해제
export RMW_IMPLEMENTATION=rmw_zenoh_cpp
```
