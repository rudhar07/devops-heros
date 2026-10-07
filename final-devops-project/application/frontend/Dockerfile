# TaskBoard UI image. Multi-stage: Node builds the static files, an
# unprivileged nginx serves them. No Node, npm or sources in the final image.

# ---------- stage 1: build ----------
FROM node:24-alpine@sha256:ebfe2f90462722a7a4de65e91990e97fe0d401c70e0e762c5b53302f905ec1c1 AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY index.html vite.config.js ./
COPY src ./src
RUN npm test && npm run build

# ---------- stage 2: runtime ----------
# nginx-unprivileged runs as UID 101 and listens on 8080 (no root, no port 80).
FROM nginxinc/nginx-unprivileged:1.30-alpine@sha256:15c994d10d6d78658721c3bcafff14cb281fba2a4bdf9d5ba92c416a472516e3

LABEL org.opencontainers.image.source="https://github.com/rudhar07/devops-heros" \
      org.opencontainers.image.description="TaskBoard UI (React + nginx) - DevOps final project"

# Pick up Alpine security fixes published after the base image was built
# (first scan found zlib CVE-2026-85091, MEDIUM, fixed in 1.3.2-r1).
USER root
RUN apk upgrade --no-cache

ENV BACKEND_URL=http://backend:8000
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html

USER 101
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/healthz"]
