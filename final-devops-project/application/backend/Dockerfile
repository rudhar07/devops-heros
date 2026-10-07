# TaskBoard API image.
# Base pinned by digest (multi-arch index of python:3.13-slim-trixie), so CI
# builds exactly the base that was scanned. Same base as my session 17 image.
FROM python:3.13-slim-trixie@sha256:bf44cdfcb76cd3b41e879bc058fc37ec5872002ccfde7fcb765e218cde0cd79c

LABEL org.opencontainers.image.source="https://github.com/rudhar07/devops-heros" \
      org.opencontainers.image.description="TaskBoard API (FastAPI) - DevOps final project"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
# pip is only needed at build time. Uninstalling it also removes its vendored
# libraries, which Trivy otherwise reports as HIGH (lesson from session 17).
RUN pip install -r requirements.txt \
 && pip uninstall -y pip \
 && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

COPY alembic.ini ./
COPY alembic ./alembic
COPY app ./app

ARG GIT_SHA=local
ENV GIT_SHA=${GIT_SHA}

# Fixed numeric UID so Kubernetes can enforce runAsNonRoot.
USER 10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

# Migrations are NOT run here: Compose runs a one-shot "migrate" service and
# Kubernetes runs an initContainer ("alembic upgrade head") with the same image.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*", "--no-server-header"]
