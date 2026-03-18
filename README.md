# UWB Recon

UWB 기반 정찰 시스템을 위한 Docker 개발 환경. Ubuntu 22.04 위에 ROS2 Humble, PX4 SITL, uXRCE-DDS Agent를 통합 구성합니다.

## 구성 요소

| 구성 요소 | 설명 |
|-----------|------|
| **ROS2 Humble** | 로봇 통신 프레임워크 (Desktop 풀 설치) |
| **PX4-Autopilot** | 드론 SITL 시뮬레이션 환경 |
| **Micro XRCE-DDS Agent** | PX4 ↔ ROS2 브릿지 (uORB → DDS) |
| **px4_msgs** | PX4 ROS2 메시지 패키지 |

## Quick Start

```bash
# 1. 환경변수 설정
cp .env.example .env

# 2. 이미지 빌드
bash scripts/build.sh

# 3. 컨테이너 실행
bash scripts/run.sh
```

## 실행 모드

### Docker Compose (기본)

```bash
bash scripts/run.sh          # 시작 (기존 컨테이너가 있으면 재사용)
bash scripts/stop.sh         # 중지 (컨테이너 유지)
bash scripts/stop.sh --down  # 중지 및 컨테이너 삭제
```

### Standalone

단일 컨테이너로 직접 실행:

```bash
bash scripts/run.sh --standalone
bash scripts/stop.sh --standalone
```

## 파일 구조

```
.
├── Dockerfile              # Ubuntu 22.04 + ROS2 + PX4 + uXRCE-DDS
├── docker-compose.yml      # GPU/X11/host network 설정
├── ros_entrypoint.sh       # ROS2 환경 자동 소싱
├── .env.example            # 환경변수 템플릿
├── .dockerignore
├── .gitignore
└── scripts/
    ├── build.sh            # 이미지 빌드 (bash scripts/build.sh [태그])
    ├── run.sh              # 서비스 시작 (--standalone 옵션)
    └── stop.sh             # 서비스 중지 (--down, --down-volumes 옵션)
```

## 컨테이너 내부 구조

| 경로 | 내용 |
|------|------|
| `/opt/ros/humble/` | ROS2 Humble 설치 경로 |
| `/root/PX4-Autopilot/` | PX4 SITL 소스 |
| `/root/ros2_ws/` | px4_msgs colcon 워크스페이스 |

## 요구 사항

- Docker & Docker Compose
- NVIDIA GPU + [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) (Gazebo GUI 렌더링용)
- X11 디스플레이 (GUI 사용 시)
