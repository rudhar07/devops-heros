# Base image pinned by digest (multi-arch index of python:3.13-slim-trixie),
# so a rebuild cannot silently pick up a different base.
FROM python:3.13-slim-trixie@sha256:bf44cdfcb76cd3b41e879bc058fc37ec5872002ccfde7fcb765e218cde0cd79c

LABEL org.opencontainers.image.source="https://github.com/rudhar07/devops-heros" \
      org.opencontainers.image.description="Session 16 CI/CD homework - calculator API"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Dependencies first so this layer is cached when only the code changes
COPY requirements.txt .
# pip is only needed to install the dependencies. Removing it afterwards
# also removes its vendored libraries (urllib3, msgpack, ...) that Trivy
# reported as HIGH in my first scan.
RUN pip install -r requirements.txt \
 && pip uninstall -y pip

COPY app ./app

# Which commit this image was built from (shown by GET /)
ARG GIT_SHA=local
ENV GIT_SHA=${GIT_SHA}

# Run as an unprivileged user, not root
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
USER 10001

EXPOSE 8000
# --no-control-socket: gunicorn 26 otherwise tries to create a control socket
# in $HOME, which this user does not have (we do not use gunicornc anyway).
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "--no-control-socket", "--access-logfile", "-", "app.web:app"]
