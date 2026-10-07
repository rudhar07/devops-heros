# Slim base, pinned by digest (multi-arch index of python:3.13-slim-trixie),
# so every build uses exactly the base image that was scanned.
FROM python:3.13-slim-trixie@sha256:bf44cdfcb76cd3b41e879bc058fc37ec5872002ccfde7fcb765e218cde0cd79c

LABEL org.opencontainers.image.source="https://github.com/rudhar07/devops-heros" \
      org.opencontainers.image.description="Session 17 DevSecOps homework - DevSecOps dashboard"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY requirements.txt .
# pip is only needed to install the dependencies. Removing it afterwards
# also removes its vendored libraries (urllib3, msgpack, ...) that Trivy
# reported as HIGH in my first scan.
RUN pip install -r requirements.txt \
 && pip uninstall -y pip

COPY app ./app

ARG GIT_SHA=local
ENV GIT_SHA=${GIT_SHA}

# Non-root user with a fixed UID, so Kubernetes can check runAsNonRoot
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8080
# Used by plain "docker run" (Kubernetes uses the probes in k8s/deployment.yaml)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=2)"]
# gunicorn instead of the Flask dev server. Worker heartbeat files go to
# /tmp, which is an emptyDir in Kubernetes (root filesystem is read-only).
# --no-control-socket: gunicorn 26 otherwise tries to create a control socket
# in $HOME, which this user does not have (and we do not use gunicornc).
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "--worker-tmp-dir", "/tmp", "--no-control-socket", "--access-logfile", "-", "app.app:app"]
