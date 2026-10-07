# docker/

Only the Compose file lives here. The two Dockerfiles stay next to the code they build:

| Image | Dockerfile | Notes |
|---|---|---|
| `taskboard-backend` | `../application/backend/Dockerfile` | python:3.13-slim (digest-pinned), pip removed after install, UID 10001 |
| `taskboard-frontend` | `../application/frontend/Dockerfile` | multi-stage: node:24-alpine build -> nginx-unprivileged (UID 101, port 8080) |

Keeping each Dockerfile beside its source means the build context is just that folder
(small context, a `.dockerignore` per app), and CI builds with `docker build application/backend`.

```bash
cd final-devops-project
docker compose -f docker/docker-compose.yml up --build -d
curl http://localhost:18090/api/tasks        # through the frontend nginx proxy
docker compose -f docker/docker-compose.yml down -v
```

Services: `postgres` (healthcheck) -> `migrate` (one-shot `alembic upgrade head`) -> `backend`
(waits for the migration to finish) -> `frontend` (waits for the backend healthcheck).
