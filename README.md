# Docker Workspace Template

Docker 환경 구축을 위한 미니멀 템플릿. main 브랜치를 기본 템플릿으로 유지하고, 프로젝트별 브랜치를 생성하여 사용합니다.

## Quick Start

```bash
# 1. 리포지토리 클론
git clone https://github.com/Porofly/docker_workspace.git
cd docker_workspace

# 2. 프로젝트 브랜치 생성
git checkout -b project/my-project

# 3. 환경변수 설정
cp .env.example .env
# .env 파일을 프로젝트에 맞게 수정

# 4. 빌드
bash scripts/build.sh

# 5. 실행
bash scripts/run.sh
```

## 브랜칭 워크플로우

```
main (템플릿)
├── project/web-api        # 웹 API 프로젝트
├── project/data-pipeline  # 데이터 파이프라인
└── project/ml-service     # ML 서비스
```

- **main**: 템플릿 원본. 직접 수정하지 않음
- **project/xxx**: main에서 분기하여 프로젝트별 커스터마이즈
- 프로젝트 브랜치는 main에 머지하지 않음
- 템플릿 업데이트 반영: `git merge main` (프로젝트 브랜치에서)

## 파일 구조

| 파일 | 설명 |
|------|------|
| `Dockerfile` | 싱글스테이지 빌드 템플릿 (`[커스터마이즈]` 주석 참고) |
| `docker-compose.yml` | app + PostgreSQL 구성, 선택 서비스(Redis, Nginx) 포함 |
| `.env.example` | 환경변수 템플릿 (`.env`로 복사하여 사용) |
| `.dockerignore` | Docker 빌드 제외 파일 |
| `.gitignore` | Git 추적 제외 파일 |
| `scripts/build.sh` | 이미지 빌드 (`bash scripts/build.sh [태그]`) |
| `scripts/run.sh` | 서비스 시작 (`--standalone`: 단일 컨테이너 모드) |
| `scripts/stop.sh` | 서비스 중지 (`--volumes`: 볼륨 삭제) |

## 사용 모드

### Docker Compose (기본)
여러 서비스가 필요한 경우 (app + DB 등):
```bash
bash scripts/run.sh       # 시작
bash scripts/stop.sh      # 중지
```

### Standalone
단일 컨테이너만 필요한 경우:
```bash
bash scripts/build.sh
bash scripts/run.sh --standalone
bash scripts/stop.sh --standalone
```

## 커스터마이즈 체크리스트

새 프로젝트 브랜치에서 아래 항목을 수정하세요:

- [ ] `Dockerfile`: 베이스 이미지, 패키지, 빌드 단계, 실행 명령
- [ ] `docker-compose.yml`: 서비스 구성, 포트, 볼륨
- [ ] `.env.example`: 프로젝트에 맞는 환경변수
- [ ] `.dockerignore`: 언어별 제외 항목 주석 해제
- [ ] `README.md`: 프로젝트 설명으로 교체
