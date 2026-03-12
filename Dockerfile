# ============================================
# Docker Workspace Template
# ============================================
# 이 Dockerfile을 프로젝트에 맞게 수정하세요.
# 주석의 [커스터마이즈] 표시를 참고하세요.

# [커스터마이즈] 베이스 이미지를 프로젝트에 맞게 변경
# 예: node:20-slim, python:3.12-slim, golang:1.22-bookworm
# ARG BASE_IMAGE=debian:bookworm-slim
# FROM ${BASE_IMAGE}

# LABEL maintainer="your-email@example.com"
# LABEL description="Docker workspace template"

# 시스템 패키지 설치
# [커스터마이즈] 필요한 패키지를 추가/제거
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     curl \
#     ca-certificates \
#     && rm -rf /var/lib/apt/lists/*

# 비루트 사용자 생성 (보안)
# RUN groupadd -r appuser && useradd -r -g appuser -m appuser

# 작업 디렉토리 설정
# WORKDIR /app

# [커스터마이즈] 의존성 파일 복사 및 설치
# 예: COPY package.json package-lock.json ./
#     RUN npm ci
# 예: COPY requirements.txt ./
#     RUN pip install -r requirements.txt

# [커스터마이즈] 소스 코드 복사
# COPY --chown=appuser:appuser . .

# 비루트 사용자로 전환
# USER appuser

# [커스터마이즈] 포트 노출
# EXPOSE 8080

# [커스터마이즈] 헬스체크
# HEALTHCHECK --interval=30s --timeout=3s \
#     CMD curl -f http://localhost:8080/health || exit 1

# [커스터마이즈] 실행 명령
# 예: CMD ["node", "server.js"]
# 예: CMD ["python", "app.py"]
# CMD ["bash"]
