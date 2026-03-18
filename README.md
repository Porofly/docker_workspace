# Suicide Drone — PX4 + ROS2 + Gazebo + YOLOv8

PX4 자율비행 드론 개발을 위한 Docker 환경. ROS2 Humble, Gazebo Classic, YOLOv8(CUDA 11.8)을 포함합니다.

## 포함 스택

| 구성 요소 | 버전 |
|-----------|------|
| Ubuntu | 22.04 |
| ROS2 | Humble (Desktop) |
| RMW | Zenoh (`rmw_zenoh_cpp`) |
| PX4-Autopilot | latest (recursive clone) |
| Micro XRCE-DDS Agent | v2.4.3 |
| YOLOv8 | ultralytics (PyTorch CUDA 11.8) |
| GStreamer | 1.0 (영상 스트리밍) |

## 요구 사항

- Docker + Docker Compose
- NVIDIA GPU + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html)
- X11 디스플레이 서버 (Gazebo GUI 사용 시)

## Quick Start

```bash
# 1. 환경변수 설정
cp .env.example .env

# 2. 이미지 빌드
bash scripts/build.sh

# 3. 컨테이너 실행
bash scripts/run.sh

# 4. 컨테이너 접속
docker exec -it px4-ros2-dev bash
```

## 파일 구조

| 파일 | 설명 |
|------|------|
| `Dockerfile` | PX4 + ROS2 Humble + Gazebo + YOLOv8 통합 이미지 |
| `docker-compose.yml` | GPU 패스스루, X11 포워딩, 볼륨 마운트 설정 |
| `.env.example` | 환경변수 템플릿 (`PROJECT_NAME`, `DISPLAY`) |
| `scripts/build.sh` | 이미지 빌드 (`bash scripts/build.sh [태그]`) |
| `scripts/run.sh` | 컨테이너 생성/시작 (X11 포워딩 자동 설정) |
| `scripts/stop.sh` | 컨테이너 중지 (`--rm`: 컨테이너 삭제) |
| `src/` | ROS2 사용자 패키지 (컨테이너 내 `/root/ros2_ws/src/user_pkg`에 마운트) |

## 컨테이너 설정

- **네트워크**: `host` 모드 (DDS 통신을 위해)
- **GPU**: 전체 NVIDIA GPU 패스스루
- **볼륨**: `./src` → `/root/ros2_ws/src/user_pkg` (호스트에서 편집, 컨테이너에서 빌드)
- **RMW**: `rmw_zenoh_cpp` (기본값, `.bashrc`에서 `rmw_fastrtps_cpp`로 변경 가능)

## 스크립트 사용법

```bash
# 빌드 (태그 지정 가능)
bash scripts/build.sh          # px4-ros2-dev:latest
bash scripts/build.sh v1.0     # px4-ros2-dev:v1.0

# 실행 (기존 컨테이너가 있으면 재시작, 없으면 새로 생성)
bash scripts/run.sh

# 중지 (컨테이너 유지)
bash scripts/stop.sh

# 중지 + 컨테이너 삭제
bash scripts/stop.sh --rm
```

## 컨테이너 내부 작업

```bash
# PX4 SITL 시뮬레이션 시작
cd /root/PX4-Autopilot
make px4_sitl gazebo-classic

# Micro XRCE-DDS Agent 실행
MicroXRCEAgent udp4 -p 8888

# ROS2 토픽 확인
ros2 topic list
```
