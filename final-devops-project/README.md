# DevOps Final Project (Session 21) - TaskBoard, end to end

**Name:** Rudhar Bajaj (roll number 10143)
**Repository:** https://github.com/rudhar07/devops-heros (this folder: `final-devops-project/`)
**Environment:** macOS (Apple Silicon), Docker Desktop (Engine 29.6.1, ~8 GB for the VM), kind v0.33.0
(node image v1.37.0), kubectl 1.36.1, Helm 4.3.0, Terraform 1.16.4 + LocalStack 4.14.0 community,
Trivy 0.75.0, Gitleaks 8.30.1, Bandit 1.9.4, pip-audit 2.10.1, ArgoCD 3.5.4, kube-prometheus-stack 92.1.0
(Grafana 13.2.3), ingress-nginx 1.15.1, metrics-server 0.9.0, actionlint 1.7.12.

Every output block below is real output from commands I ran on 2026-10-07 and 2026-10-08 (one
session that went past midnight IST; containers log in UTC, so most timestamps inside them still say
2026-10-07). Full untrimmed transcripts are in [`outputs/`](outputs/), each command shown as a `$ command`
line before its output. Where I shortened a listing I say so. Things that could not run on my laptop
(real AWS, the GitHub Actions run itself) are marked as such, with the closest real thing I did.

---

## Contents

1. [Project overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Technologies used](#3-technologies-used)
4. [Repository layout](#4-repository-layout)
5. [Transcripts and screenshots](#5-transcripts-and-screenshots)
6. [Application setup](#6-application-setup)
7. [Docker setup](#7-docker-setup)
8. [Kubernetes deployment (raw manifests)](#8-kubernetes-deployment-raw-manifests)
9. [Helm deployment](#9-helm-deployment)
10. [Autoscaling (HPA)](#10-autoscaling-hpa)
11. [Terraform infrastructure](#11-terraform-infrastructure)
12. [CI/CD pipeline](#12-cicd-pipeline)
13. [DevSecOps](#13-devsecops)
14. [Monitoring and logs](#14-monitoring-and-logs)
15. [GitOps](#15-gitops)
16. [Troubleshooting challenge](#16-troubleshooting-challenge)
17. [Lessons learned](#17-lessons-learned)
18. [Grading rubric mapping (GRADING.md)](#18-grading-rubric-mapping)
19. [Honest notes: what differs from the spec](#19-honest-notes-what-differs-from-the-spec)

---

## 1. Project overview

TaskBoard is a small project-management app for a platform team: create tasks, give them a
priority, assignee and due date, move them TODO -> IN_PROGRESS -> DONE, search and filter them, and
see KPIs (open high-priority work, overdue tasks). The point of the project is not the app itself
but the path it takes:

```
code -> Git/GitHub -> CI (tests, SAST, SCA, secrets, IaC scan) -> Docker images -> Trivy gate
     -> GHCR -> Kubernetes (Helm, Ingress, HPA, probes, PVC) -> Prometheus/Grafana -> ArgoCD (GitOps)
```

I started from the instructor's reference in `session21-python/` (left untouched) and copied the
backend and frontend into `application/`. Several reference files were one-line stubs or had bugs, so
this is what I changed or added:

| Area | Reference (`session21-python/`) | This project |
|---|---|---|
| API | CRUD + stats | + `/api/info`, filters (`status`, `priority`), search `q`, paging, `/ready` returns **503** when the DB is down, business metric `taskboard_task_events_total` |
| Data | 1 migration | + migration `0002` (due_date, updated_at, indexes); Postgres advisory lock so parallel pods migrate one at a time |
| Config | one `DATABASE_URL` | `DB_HOST/PORT/NAME` from a ConfigMap, `DB_USER/PASSWORD` from a Secret (URL built with escaping) |
| Tests | 3 tests, wrote to `./test.db` | 24 tests, in-memory SQLite via `conftest.py`, migration up/down test, 98 % coverage |
| Frontend | single-line `main.jsx`, `"latest"` deps, no lockfile | components, edit/delete/search/due dates, error states, responsive table, pinned deps + lockfile, 5 unit tests |
| Images | root nginx on port 80, pip left in image | nginx-unprivileged (UID 101, 8080), pip removed, digest-pinned bases, HEALTHCHECKs |
| Helm | Ingress pointed at `taskboard-backend:8080` (Service was `<release>-taskboard-backend:8000`), nginx proxied to a host `backend` that does not exist in k8s, frontend name not release-aware | consistent names/labels, named ports, ConfigMap + Secret, initContainers (wait-for-db, migrate), securityContext, PrometheusRule, `helm test`, values-dev/prod/gitops |
| Terraform | 2-line `main.tf` with modules | full VPC/subnets/IGW/NAT/routes/SGs/S3/ECR/IAM/EKS(+KMS) written out, LocalStack switch |
| CI | trivy-action, `latest`-free but no SAST/SCA/secrets | 12-job pipeline with a security gate (section 12) |

## 2. Architecture

```mermaid
flowchart LR
    dev[Developer] -->|git push| gh[(GitHub<br/>rudhar07/devops-heros)]
    gh --> ci[GitHub Actions<br/>session21-final.yml]
    subgraph CI[CI pipeline]
      ci --> t[pytest + node --test<br/>vite build]
      t --> s[Bandit / pip-audit / npm audit<br/>Gitleaks / Trivy fs + config]
      t --> b[docker build x2]
      b --> sc[Trivy image gate]
      s & sc --> gate{security gate}
    end
    gate -->|main only| ghcr[(GHCR<br/>tags: SHA + appVersion)]
    ghcr --> kindci[kind in runner<br/>helm upgrade --install + smoke test]
    gh -->|watched by| argo[ArgoCD]
    argo -->|sync + selfHeal| k8s
    tf[Terraform] -->|VPC, subnets, NAT, SGs,<br/>S3, ECR, IAM, EKS| aws[(AWS / LocalStack)]
    subgraph k8s[Kubernetes cluster]
      ing[ingress-nginx] -->|/| fe[frontend x2<br/>nginx + React]
      ing -->|/api| be[backend x2..4<br/>FastAPI, HPA]
      fe -.->|/api proxy| be
      be --> pg[(PostgreSQL<br/>PVC)]
      prom[Prometheus] -->|ServiceMonitor /metrics| be
      graf[Grafana] --> prom
    end
    user[Browser] --> ing
```

ASCII version (same thing, for terminals):

```
 Developer --push--> GitHub --> GitHub Actions: test -> scan -> build -> Trivy -> gate -> GHCR -> kind deploy
                        |
                        +--(watched by)--> ArgoCD --sync/self-heal--+
                                                                    v
 Browser --> ingress-nginx --/----> frontend Service --> nginx pods (React SPA, /api proxy fallback)
                         \--/api--> backend Service ---> FastAPI pods (2-4, HPA on CPU) --> PostgreSQL (PVC)
                                         ^
                 Prometheus --ServiceMonitor (/metrics)--+   Grafana --> Prometheus   Alertmanager <-- rules
 Terraform --> AWS: VPC 10.20.0.0/16, 2 public + 2 private subnets, IGW, NAT, SGs, S3, ECR, IAM, EKS + node group
```

## 3. Technologies used

| Layer | Tool (version I used) | Where |
|---|---|---|
| Backend | Python 3.13, FastAPI 0.142, SQLAlchemy 2.1, Alembic 1.20, psycopg 3.3, uvicorn 0.54 | `application/backend` |
| Metrics | prometheus-fastapi-instrumentator 8.1, prometheus-client 0.26 | `app/main.py`, `app/metrics.py` |
| Frontend | React 19.3, Vite 8.3, nginx 1.30 (nginx-unprivileged) | `application/frontend` |
| Database | PostgreSQL 17.11 (alpine) | Compose, Helm, raw manifests |
| Tests | pytest 9.1 + pytest-cov 7.1, node:test | `tests/`, `src/lib/*.test.js` |
| Containers | Docker 29.6, Compose v2 | `*/Dockerfile`, `docker/docker-compose.yml` |
| Kubernetes | kind (k8s 1.37), ingress-nginx 1.15.1, metrics-server 0.9.0 | `kubernetes/` |
| Packaging | Helm 4.3 | `helm/taskboard` |
| IaC | Terraform 1.16 + AWS provider 6.67, LocalStack 4.14 | `terraform/` |
| CI/CD | GitHub Actions, GHCR, kind in the runner | `.github/workflows/session21-final.yml` (repo root) |
| Security | Bandit, pip-audit, npm audit, Gitleaks, Trivy (fs, config, image) | `security/` |
| Observability | kube-prometheus-stack 92.1 (Prometheus, Alertmanager, Grafana 13.2) | `monitoring/` |
| GitOps | ArgoCD 3.5.4 | `gitops/` |

## 4. Repository layout

```
final-devops-project/
├── application/
│   ├── backend/        FastAPI app, Alembic migrations, tests, Dockerfile, requirements*.txt
│   └── frontend/       React (Vite) app, nginx.conf.template, Dockerfile (multi-stage), package-lock.json
├── docker/             docker-compose.yml (+ README: why the Dockerfiles stay next to the code)
├── kubernetes/         raw manifests: Namespace, ConfigMap, Secret template, Postgres (PVC), backend,
│                       frontend, Ingress, HPA, and the kind cluster config
├── helm/taskboard/     chart + values.yaml, values-dev.yaml, values-prod.yaml, values-gitops.yaml
├── terraform/          VPC, subnets, NAT, SGs, S3, ECR, IAM, EKS (+ localstack.tfvars, tfvars.example)
├── .github/workflows/  reference copy of the workflow (the live one is at the repo root)
├── security/           bandit.yaml, .gitleaks.toml, trivy.yaml, .trivyignore, reports/
├── monitoring/         kube-prometheus-stack values, Grafana dashboard JSON, ServiceMonitor, alert rules
├── gitops/             ArgoCD Application (GitHub) + the local demo variant
├── troubleshooting/    6 broken setups + the instructor's 2 broken manifests
├── scripts/            load-test.sh (in-cluster load for the HPA), kind-load.sh
└── outputs/            transcripts (*.txt) and 4 real browser screenshots (screenshots/*.png)
```

Mapping from the instructor's layout: `session21-python/k8s/namespace.yaml` -> `kubernetes/00-namespace.yaml`,
`helm/` -> `helm/`, `monitoring/prometheus-values.yaml` -> `monitoring/kube-prometheus-stack-values.yaml`,
`.github/workflows/ci-cd.yml` -> repo-root `.github/workflows/session21-final.yml` (GitHub only runs
workflows from the repository root, so the copy under `final-devops-project/.github/` is for reference).

## 5. Transcripts and screenshots

The homework asks for screenshots. As in my earlier sessions, committed text transcripts replace most
of them; I quote the key lines in each section. For the UI and Grafana I also took real browser
screenshots (Playwright/Chromium against the running app).

| File | What it shows |
|---|---|
| `outputs/01-tests.txt` | pytest -v with coverage (24 passed, 97.94 %), frontend tests and build |
| `outputs/02-docker-build.txt` | both image builds, sizes, non-root users, no pip / no node in the final images |
| `outputs/03-compose-up.txt` | `docker compose up --build --wait`: postgres -> migrate -> backend -> frontend |
| `outputs/04-compose-crud.txt` | full CRUD through the frontend nginx proxy, rows in PostgreSQL, /metrics |
| `outputs/05-sast-sca.txt` | Bandit, pip-audit, npm audit, Trivy fs |
| `outputs/06-trivy-image.txt` | Trivy image scans + gate, one CVE explained, frontend fix |
| `outputs/07-cluster-setup.txt` | kind `hw-f`, ingress-nginx, metrics-server |
| `outputs/08-helm-deploy.txt` | Helm install (first attempt failed, debugged), final rollout, read-only postgres |
| `outputs/09-ingress-and-api.txt` | UI + CRUD through the Ingress, `helm test` |
| `outputs/10-hpa-load-test.txt` | HPA 2 -> 4 -> 2 under load |
| `outputs/11-raw-manifests.txt` | raw manifests: server dry-run + real apply in a separate namespace |
| `outputs/12-monitoring-install.txt` | kube-prometheus-stack install, ServiceMonitor/PrometheusRule |
| `outputs/13-prometheus-promql.txt` | targets UP, 8 PromQL queries with results, alert rules |
| `outputs/14-grafana.txt` | Grafana health, datasource, dashboard API, OOMKill fix |
| `outputs/15..20-tshoot-*.txt` | the 6 troubleshooting cases |
| `outputs/21-argocd-install.txt`, `22-gitops.txt` | ArgoCD install, sync, Git change, drift self-heal |
| `outputs/23-logs.txt` | one request followed through ingress, backend, postgres logs |
| `outputs/24-terraform.txt` | init / fmt / validate / plan / apply / output / verify / destroy on LocalStack |
| `outputs/25-iac-misconfig-scan.txt` | Trivy config scan before/after the IaC fixes |
| `outputs/26-actionlint-and-ci-rehearsal.txt` | actionlint on all root workflows, local rehearsal of the compose-e2e CI job |
| `outputs/27-final-cluster-state.txt` | everything running at the end, before cleanup |
| `outputs/28-gitleaks-final.txt` | final secret scan of the finished folder (7 hits on the fake Grafana password, fixed) |
| `outputs/29-cleanup.txt` | kind cluster, git daemon, images and volumes removed |
| `outputs/screenshots/01-compose-ui.png` | UI from Docker Compose (localhost:18090) |
| `outputs/screenshots/02-kind-ingress-ui.png` | UI through the Kubernetes Ingress (taskboard.localhost:30110) |
| `outputs/screenshots/03-mobile-layout.png` | same page at 390 px width (responsive layout) |
| `outputs/screenshots/04-grafana-dashboard.png` | Grafana dashboard with live data |

**GitHub Actions run:** <!-- RUN-LINK: filled in after the first push -->

![TaskBoard through the Ingress](outputs/screenshots/02-kind-ingress-ui.png)

---

## 6. Application setup

### API

| Method | Path | Notes |
|---|---|---|
| GET | `/health` | liveness, no DB access |
| GET | `/ready` | readiness, `SELECT 1`; **503** `{"status":"NOT_READY"}` if PostgreSQL is unreachable |
| GET | `/metrics` | Prometheus text format (not exposed through the Ingress) |
| GET | `/`, `/api/info` | service, version, environment, commit SHA |
| GET | `/api/tasks?status=&priority=&q=&limit=&offset=` | list, newest first, filters + search |
| GET | `/api/tasks/{id}` | one task, 404 if missing |
| POST | `/api/tasks` | create, 201; 422 on validation errors |
| PUT | `/api/tasks/{id}` | partial update (only the fields sent) |
| DELETE | `/api/tasks/{id}` | 204 |
| GET | `/api/tasks/stats` | totals per status, open high-priority, overdue |

### Run it locally without containers

```bash
cd final-devops-project/application/backend
python3.13 -m venv ~/.venvs/taskboard && source ~/.venvs/taskboard/bin/activate   # venv outside the repo
pip install -r requirements-dev.txt
export DATABASE_URL='postgresql+psycopg://taskboard:demo-password-123@localhost:5432/taskboard'   # fake demo password
alembic upgrade head
uvicorn app.main:app --reload --port 8000
cd ../frontend && npm ci && npm run dev        # Vite on :5173, proxies /api to :8000
```

### Tests

`conftest.py` swaps the app's `get_db` dependency for a fresh **in-memory SQLite** database per test,
so the real PostgreSQL is never touched. A separate test runs the Alembic migrations up and down on a
temporary SQLite file, so a migration that does not match the models fails CI.

```
$ python -m pytest -v -p no:cacheprovider --cov=app --cov-report=term-missing --cov-fail-under=80
tests/test_api.py::test_health PASSED                                    [  4%]
...
tests/test_config_and_migrations.py::test_alembic_migrations_upgrade_and_downgrade PASSED [100%]
Name              Stmts   Miss Branch BrPart  Cover   Missing
app/main.py          96      0     10      0   100%
...
TOTAL               182      4     12      0    98%
Required test coverage of 80% reached. Total coverage: 97.94%
============================== 24 passed in 0.30s ==============================

$ npm test
✔ nextStatus cycles TODO -> IN_PROGRESS -> DONE -> TODO (0.317375ms)
...
ℹ tests 5
ℹ pass 5
```

(trimmed, full output in `outputs/01-tests.txt`; the 4 uncovered lines are the real `get_db()` that
the tests deliberately replace.)

**What I observed:** the first run printed two deprecation warnings: Starlette 1.x wants `httpx2` for
its TestClient, and Alembic wanted `path_separator` in `alembic.ini`. I fixed both instead of hiding
them, and `pytest.ini` now turns deprecation warnings from my own `app` package into errors.

---

## 7. Docker setup

Both Dockerfiles live next to their code (`application/backend/Dockerfile`,
`application/frontend/Dockerfile`), so each build context is only that folder; `docker/` holds the
Compose file. Reason in `docker/README.md`.

| | Backend | Frontend |
|---|---|---|
| Base | `python:3.13-slim-trixie@sha256:bf44...` (digest-pinned) | build: `node:24-alpine@sha256:ebfe...`, runtime: `nginxinc/nginx-unprivileged:1.30-alpine@sha256:15c9...` |
| Multi-stage | no (pip removed after install instead) | yes: Node builds `dist/`, only static files reach nginx |
| User | UID 10001 | UID 101, port 8080 |
| Migrations | not in CMD; Compose `migrate` service / k8s initContainer | - |
| Size | 305 MB (containerd store, incl. attestations) | 90.6 MB |

```
$ docker run --rm --entrypoint id taskboard-backend:local
uid=10001(appuser) gid=10001(appuser) groups=10001(appuser)
$ docker run --rm --entrypoint id taskboard-frontend:local
uid=101(nginx) gid=101(nginx) groups=101(nginx),101(nginx)
$ docker run --rm --entrypoint sh taskboard-backend:local -c 'python -m pip --version || echo pip not present in the final image'
/usr/local/bin/python: No module named pip
pip not present in the final image
```

Compose (`docker/docker-compose.yml`): `postgres` (healthcheck) -> `migrate` (one-shot
`alembic upgrade head`, must exit 0) -> `backend` (read-only root FS, healthcheck) -> `frontend`.
Host ports 18090 (UI + API through nginx) and 18091 (API directly).

```
$ docker compose -f docker/docker-compose.yml ps -a --format 'table {{.Service}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
SERVICE    IMAGE                      STATUS                      PORTS
backend    taskboard-backend:local    Up 11 seconds (healthy)     0.0.0.0:18091->8000/tcp, [::]:18091->8000/tcp
frontend   taskboard-frontend:local   Up 5 seconds (healthy)      0.0.0.0:18090->8080/tcp, [::]:18090->8080/tcp
migrate    taskboard-backend:local    Exited (0) 11 seconds ago
postgres   postgres:17.11-alpine      Up 16 seconds (healthy)     5432/tcp

$ docker compose -f docker/docker-compose.yml logs migrate
migrate-1  | INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tasks, create tasks table
migrate-1  | INFO  [alembic.runtime.migration] Running upgrade 0001_create_tasks -> 0002_due_date_updated_at, ...
```

CRUD through the frontend's nginx (`outputs/04-compose-crud.txt`, trimmed):

```
$ curl -s -X POST http://localhost:18090/api/tasks -H 'Content-Type: application/json' -d '{"title":"Write Helm chart",...,"due_date":"2026-10-10"}'
{"title":"Write Helm chart","description":"values-dev and values-prod","priority":"HIGH","status":"TODO","assignee":"Rudhar","due_date":"2026-10-10","id":1,...}
$ curl -s http://localhost:18090/api/tasks/stats
{"total":3,"todo":2,"inProgress":1,"done":0,"highPriorityOpen":1,"overdue":1}
$ curl -s -X PUT http://localhost:18090/api/tasks/1 -H 'Content-Type: application/json' -d '{"status":"DONE"}'
{"title":"Write Helm chart",...,"status":"DONE",...}
DELETE /api/tasks/3 -> HTTP 204
{"detail":"Task not found"}
HTTP 404
$ docker compose -f docker/docker-compose.yml exec -T postgres psql -U taskboard -d taskboard -c 'SELECT id, title, status, priority, due_date FROM tasks ORDER BY id;'
 id |      title       |   status    | priority |  due_date
----+------------------+-------------+----------+------------
  1 | Write Helm chart | DONE        | HIGH     | 2026-10-10
  2 | Add Trivy gate   | IN_PROGRESS | MEDIUM   |
```

![TaskBoard from Docker Compose](outputs/screenshots/01-compose-ui.png)

---

## 8. Kubernetes deployment (raw manifests)

Cluster: kind `hw-f`, one node, host port 30110 -> ingress-nginx (`kubernetes/kind-hw-f.yaml`), plus
ingress-nginx and metrics-server (`outputs/07-cluster-setup.txt`). All my kubectl/helm commands used a
private kubeconfig, never `~/.kube/config`.

`kubernetes/` has every object written out by hand: Namespace, ConfigMap, Secret **template with a
fake password**, PostgreSQL PVC + Deployment (Recreate) + Service, backend Deployment (2 replicas,
initContainers, liveness `/health`, readiness `/ready`, CPU/memory requests and limits, read-only root
FS, non-root, dropped capabilities) + Service, frontend Deployment + Service, Ingress, HPA.

I applied them into a separate namespace so they could not collide with the Helm release:

```
$ kubectl apply -n taskboard-raw --dry-run=server -f kubernetes/00-namespace.yaml -f kubernetes/01-configmap.yaml ... -f kubernetes/50-hpa.yaml
configmap/taskboard-config created (server dry run)
secret/taskboard-db created (server dry run)
persistentvolumeclaim/taskboard-postgres-data created (server dry run)
...
horizontalpodautoscaler.autoscaling/taskboard-backend created (server dry run)
$ kubectl -n taskboard-raw wait --for=condition=Available deploy --all --timeout=300s
deployment.apps/taskboard-backend condition met
deployment.apps/taskboard-frontend condition met
deployment.apps/taskboard-postgres condition met
$ curl -s http://taskboard-raw.localhost:30110/api/info
{"service":"TaskBoard API","version":"2.0.0","environment":"raw-manifests","commit":"local","docs":"/docs"}
```

**What I observed:** the very first `/api` call right after "Available" returned **503**. On a
second run I polled and read the ingress-nginx log: the controller logged
`Service "taskboard-raw/taskboard-backend" does not have any active Endpoint` and needed about 2 more
seconds to pick up the new endpoints (`00:32:20 -> 503`, `00:32:22 -> 200`). Readiness of the pods and
readiness of the load balancer's config are two different moments. Also, re-applying shows
`secret/taskboard-db configured` every time: `stringData` is write-only, so kubectl always sees a diff.

---

## 9. Helm deployment

Chart `helm/taskboard` (Chart 2.0.0, appVersion 2.0.0). Names follow `<release>-taskboard-*` unless the
release name already contains "taskboard" (release `taskboard` -> `taskboard-backend`, ...).

| values file | Used for | Key differences |
|---|---|---|
| `values.yaml` | defaults | GHCR images, 2+2 replicas, HPA 2-5, ingress `taskboard.local`, in-cluster Postgres 1Gi |
| `values-dev.yaml` | my kind cluster | `taskboard-*:local` images, ingress `taskboard.localhost`, HPA 2-4 @ 50 % |
| `values-prod.yaml` | EKS | 3 backend replicas, bigger requests, HPA 3-10, **no in-cluster Postgres** (RDS host), `existingSecret`, TLS via cert-manager annotation |
| `values-gitops.yaml` | ArgoCD | 1+1 replicas, HPA off (replicas come from Git), ingress `gitops.localhost` |

Templates: ConfigMap, Secret (skipped when `secret.existingSecret` is set), backend/frontend
Deployments + Services, Postgres PVC/Deployment/Service, Ingress, HPA, ServiceMonitor and
PrometheusRule (only rendered when the Prometheus Operator API exists), a `helm test` pod, NOTES.txt.
Config/secret checksums are pod annotations, so a changed value rolls the pods.

The first install failed, and that was useful (`outputs/08-helm-deploy.txt`):

```
$ kind load docker-image taskboard-backend:local taskboard-frontend:local postgres:17.11-alpine --name hw-f
ERROR: failed to load image: command "docker exec --privileged -i hw-f-control-plane ctr --namespace=k8s.io images import --all-platforms --digests --snapshotter=overlayfs -" failed with error: exit status 1
Command Output: ctr: content digest sha256:aa90e97e...: not found
...
pod/taskboard-backend-8f44f4655-dq6tp     0/1     Init:0/2           2 (32s ago)   5m
pod/taskboard-frontend-ddd478648-d4n8k    0/1     ImagePullBackOff   0             5m
$ kubectl -n taskboard exec deploy/taskboard-backend -c wait-for-db -- sh -c 'id; pg_isready -h $DB_HOST -p $DB_PORT; echo rc=$?; pg_isready -h $DB_HOST -p $DB_PORT -U probe; echo rc=$?'
uid=10001 gid=10001 groups=10001
taskboard-postgres:5432 - no attempt
rc=3
taskboard-postgres:5432 - accepting connections
rc=0
```

Two separate bugs: (1) Docker Desktop's containerd image store builds multi-platform images with
attestation manifests, and `kind load docker-image` (which imports `--all-platforms`) chokes on them;
`scripts/kind-load.sh` saves only `linux/arm64` and uses `kind load image-archive`. (2) My
`wait-for-db` initContainer runs as UID 10001, which has no passwd entry in the postgres image, so
`pg_isready` could not pick a user name and returned "no attempt" forever; `-U probe` fixed it.

```
$ helm upgrade --install taskboard helm/taskboard -n taskboard -f helm/taskboard/values-dev.yaml --wait --timeout 5m
Release "taskboard" has been upgraded. Happy Helming!
STATUS: deployed
REVISION: 2
$ kubectl -n taskboard logs deploy/taskboard-backend -c migrate
INFO  [alembic.runtime.migration] Running upgrade  -> 0001_create_tasks, create tasks table
INFO  [alembic.runtime.migration] Running upgrade 0001_create_tasks -> 0002_due_date_updated_at, ...
```

Through the Ingress (`/` -> frontend, `/api` -> backend), `outputs/09-ingress-and-api.txt`:

```
$ kubectl -n taskboard describe ingress taskboard | sed -n '/Rules/,/Annotations/p'
  Host                 Path  Backends
  taskboard.localhost
                       /api   taskboard-backend:http (10.244.0.16:8000,10.244.0.17:8000)
                       /      taskboard-frontend:http (10.244.0.12:8080,10.244.0.10:8080)
$ curl -s -o /dev/null -w 'HTTP %{http_code} %{content_type} %{size_download} bytes\n' http://taskboard.localhost:30110/
HTTP 200 text/html 469 bytes
$ curl -s http://taskboard.localhost:30110/api/info
{"service":"TaskBoard API","version":"2.0.0","environment":"dev","commit":"local","docs":"/docs"}
$ curl -s http://taskboard.localhost:30110/api/tasks/stats
{"total":2,"todo":0,"inProgress":1,"done":1,"highPriorityOpen":0,"overdue":0}
$ curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:30110/
HTTP 404
$ helm test taskboard -n taskboard --logs
TEST SUITE:     taskboard-test-api
Phase:          Succeeded
POD LOGS: taskboard-test-api (curl)
{"status":"UP"}{"status":"READY"}{"total":2,"todo":0,"inProgress":1,"done":1,"highPriorityOpen":0,"overdue":0}
helm test: OK
```

`taskboard.localhost` resolves to 127.0.0.1 in curl and browsers without editing `/etc/hosts`; an
unknown host gets ingress-nginx's 404, so routing really is host-based. Final state
(`outputs/27-final-cluster-state.txt`): backend 2/2, frontend 2/2, postgres 1/1, all Running, PVC Bound.

---

## 10. Autoscaling (HPA)

Backend HPA: 2-4 replicas, 50 % of the 100m CPU request. The instructor's `load-test.sh` looped 500
sequential curls from the laptop, which does not move the CPU. My `scripts/load-test.sh` starts a curl
pod **inside** the cluster with N parallel workers hitting the backend Service (`outputs/10-hpa-load-test.txt`, trimmed):

```
$ DURATION=150 WORKERS=8 scripts/load-test.sh
loadgen pod started: 8 workers x 150s against http://taskboard-backend.taskboard.svc:8000
--- 00:24:24
taskboard-backend   Deployment/taskboard-backend   cpu: 7%/50%     2     4     2     11m
--- 00:24:39
taskboard-backend   Deployment/taskboard-backend   cpu: 114%/50%   2     4     2     12m
--- 00:24:55
taskboard-backend   Deployment/taskboard-backend   cpu: 345%/50%   2     4     4     12m
...
--- 00:27:42
taskboard-backend   Deployment/taskboard-backend   cpu: 5%/50%     2     4     4     15m
--- 00:28:43
taskboard-backend   Deployment/taskboard-backend   cpu: 6%/50%     2     4     2     16m
$ kubectl -n taskboard logs loadgen --tail 10
worker 3 sent 6285 requests
...
  Normal   SuccessfulRescale   5m23s   horizontal-pod-autoscaler  New size: 4; reason: cpu resource utilization (percentage of request) above target
  Normal   SuccessfulRescale   98s     horizontal-pod-autoscaler  New size: 2; reason: All metrics below target
```

**What I observed:** scale-out took ~30 s (one metrics-server scrape + one HPA sync). Scale-in came
about 60 s after the load stopped, because I set `behavior.scaleDown.stabilizationWindowSeconds: 60`
(the default 300 s would make the demo much longer). 4 is the max, so 345 % never got more pods.
The first version of my load script did nothing: `kubectl run --overrides` replaced the whole
container spec, including the command, so curl ran with no arguments. I rewrote it as a Pod manifest.

---

## 11. Terraform infrastructure

`terraform/` describes the AWS side of the project (diagram in `terraform/README.md`):
VPC 10.20.0.0/16 in ap-south-1, **2 public + 2 private subnets** in two AZs, IGW, one NAT gateway,
public/private route tables, three security groups (load balancer -> nodes -> database), an S3
artifacts bucket (versioning, SSE-S3, public access block, lifecycle), ECR repositories (immutable
tags, scan on push), IAM roles for EKS, a KMS key, and an **EKS 1.35 cluster with a managed node group
(2-4 x t3.medium)** in the private subnets.

`use_localstack = true` points the provider at LocalStack. LocalStack 4.14.0 community does **not**
emulate EKS or ECR, and I checked that rather than assuming it:

```
$ aws --endpoint-url http://localhost:4567 eks list-clusters
aws: [ERROR]: An error occurred (InternalFailure) when calling the ListClusters operation: The API for service eks is either not included in your current license plan or has not yet been emulated by LocalStack.
```

So `localstack.tfvars` sets `enable_eks = false` and `enable_ecr = false`. Everything else is applied
for real. The EKS/ECR part is still validated and planned (`outputs/24-terraform.txt`, trimmed):

```
$ terraform init -input=false -no-color
- Installed hashicorp/aws v6.67.0 (signed by HashiCorp)
Terraform has been successfully initialized!
$ terraform fmt -check -recursive -diff && echo 'fmt: all files formatted'
fmt: all files formatted
$ terraform validate -no-color
Success! The configuration is valid.
$ terraform plan -input=false -no-color -var-file=localstack.tfvars -out=.../local.tfplan
Plan: 35 to add, 0 to change, 0 to destroy.
$ terraform plan ... -var enable_eks=true -var enable_ecr=true      (plan only, never applied here)
  # aws_eks_cluster.main[0] will be created
  # aws_eks_node_group.main[0] will be created
  # aws_kms_key.eks[0] will be created
  # aws_ecr_repository.app["taskboard-backend"] will be created
Plan: 42 to add, 0 to change, 0 to destroy.
  + resource "aws_eks_node_group" "main" {
      + cluster_name           = "taskboard-dev"
          + "t3.medium",
      + scaling_config {
          + desired_size = 2
          + max_size     = 4
          + min_size     = 2
$ terraform apply -input=false -no-color .../local.tfplan
Apply complete! Resources: 35 added, 0 changed, 0 destroyed.
$ aws --endpoint-url http://localhost:4567 ec2 describe-subnets ... --output table
|  ap-south-1a|  10.20.1.0/24    |  taskboard-dev-private-1  |  False     |
|  ap-south-1a|  10.20.101.0/24  |  taskboard-dev-public-1   |  False     |
|  ap-south-1b|  10.20.102.0/24  |  taskboard-dev-public-2   |  False     |
|  ap-south-1b|  10.20.2.0/24    |  taskboard-dev-private-2  |  False     |
$ aws ... iam list-attached-role-policies --role-name taskboard-dev-eks-nodes ...
AmazonEC2ContainerRegistryReadOnly	AmazonEKSWorkerNodePolicy	AmazonEKS_CNI_Policy
$ terraform destroy -input=false -no-color -auto-approve -var-file=localstack.tfvars
Destroy complete! Resources: 35 destroyed.
$ aws ... ec2 describe-vpcs --filters Name=tag:Project,Values=taskboard --query 'length(Vpcs)'
0
```

(The `False` column is `MapPublicIpOnLaunch`: after the IaC scan, public subnets no longer give
instances public IPs; only the NAT gateway and load balancers live there. My route-table query in the
transcript shows `None` for the private table because it printed `GatewayId` first; the NAT route is in
the plan.)

**What I observed:** a second `plan` right after `apply` wanted to change 3 security-group rules. Only
the rules that reference another SG drift: LocalStack returns `referenced_security_group_id` as
`000000000000/sg-...` and drops the description. I kept the code correct for AWS instead of adding
`ignore_changes` for the emulator.

**What would differ on real AWS:** EKS and ECR would actually be created (about 10-15 minutes for the
control plane), the NAT gateway and EKS control plane cost money per hour, `terraform.tfvars` would set
`cluster_endpoint_public_access = true` with my own /32, state would go to the S3 backend in
`backend.tf.example` (with S3-native locking), and `aws eks update-kubeconfig` (printed by the
`kubeconfig_command` output) would replace the kind kubeconfig. The rubric's "AWS Console screenshot"
is replaced by the AWS CLI queries against LocalStack above; I have no AWS account for this course.

---

## 12. CI/CD pipeline

**Live workflow (repository root):** `.github/workflows/session21-final.yml`. It runs on push and PR
to `main` when `final-devops-project/**` or the workflow itself changes, and on `workflow_dispatch`;
`defaults.run.working-directory: final-devops-project`. It reuses the patterns and action versions
that already work in my session 16/17 workflows (checkout@v7, setup-python@v7, upload-artifact@v7,
download-artifact@v8, docker/login-action@v4, helm/kind-action@v1, checksum-verified Trivy/Gitleaks).

| # | Job | What it does | Fails the build when |
|---|---|---|---|
| 1 | `backend-test` | compileall, pytest + coverage, JUnit/coverage artifacts | a test fails or coverage < 80 % |
| 2 | `frontend-build` | `npm ci`, `npm test`, `vite build`, `npm audit` | test/build fails, high/critical npm advisory |
| 3 | `sast` | Bandit JSON + SARIF report, then the gate | MEDIUM+ finding |
| 4 | `sca` | pip-audit, Trivy fs (requirements + lockfile) | any known vuln / HIGH-CRITICAL |
| 5 | `secret-scan` | Gitleaks on the project files and its git history | any secret |
| 6 | `iac-scan` | terraform fmt/validate, helm lint x4, Trivy config | invalid/unformatted code, HIGH/CRITICAL misconfig |
| 7 | `docker-build` (matrix) | builds both images tagged with the **commit SHA** | build error |
| 8 | `image-scan` (matrix) | Trivy table/JSON/SARIF, then the gate | fixable HIGH/CRITICAL |
| 9 | `compose-e2e` | the scanned images in Compose, CRUD through nginx, commit check | any curl/jq check |
| 10 | `security-gate` | table of all results in the job summary | any of 1-9 not `success` |
| 11 | `push-images` | **main only**, `permissions: packages: write`, GITHUB_TOKEN; pushes the *scanned* images as `:<sha>` and `:2.0.0` | push error |
| 12 | `deploy-kind` | kind cluster in the runner, pulls from GHCR, `helm upgrade --install`, `helm test`, smoke test incl. `/api/info.commit == $GITHUB_SHA` | any step |

Images: `ghcr.io/rudhar07/devops-heros/taskboard-backend:<sha>` and `.../taskboard-frontend:<sha>`.
No `latest` tag. The pipeline cannot run before the push, so here is what I verified locally:

```
$ cd .. && actionlint -verbose .github/workflows/session21-final.yml 2>&1 | tail -3; echo actionlint-exit=${PIPESTATUS[0]}
verbose: Found 0 parse errors in 1 ms for .github/workflows/session21-final.yml
verbose: Found total 0 errors in 141 ms for .github/workflows/session21-final.yml
actionlint-exit=0
$ cd .. && actionlint .github/workflows/session16-cicd.yml .github/workflows/session17-devsecops.yml .github/workflows/session21-final.yml && echo 'all 3 root workflows lint clean'
all 3 root workflows lint clean
```

(actionlint 1.7.12 with shellcheck 0.11.0, so the `run:` scripts were shell-checked too.) I also ran
the `compose-e2e` job's commands locally against the same images (`outputs/26-...`), ending in
`Compose CRUD OK`, and every scanner command of jobs 1-8 with the same versions and config files
(sections 6, 13). The actual GitHub run link goes here after the first push:

<!-- RUN-LINK: filled in after the first push -->

---

## 13. DevSecOps

Configs in `security/` (`security/README.md` has the gate table). Results of my local run:

| Check | Tool | Result |
|---|---|---|
| SAST | Bandit 1.9.4 (`security/bandit.yaml`) | `No issues identified.` 246 lines scanned |
| SCA Python | pip-audit 2.10.1 | `No known vulnerabilities found` |
| SCA npm | npm audit | `found 0 vulnerabilities` |
| SCA lockfiles | Trivy fs | `backend/requirements.txt 0`, `frontend/package-lock.json 0` |
| Secrets | Gitleaks 8.30.1 | first final scan: 7 findings (all the fake Grafana password in `curl -u`), then `no leaks found` (`outputs/28-gitleaks-final.txt`) |
| IaC | Trivy config | 9 HIGH/CRITICAL -> 0 (7 fixed, 2 accepted with reasons) |
| Images | Trivy image | gate exit 0 for both images |

**Gitleaks scope.** The repository also contains session-12 homework with deliberately fake secrets
for the secret-scanning lesson, so a repo-wide scan would always fail for reasons unrelated to this
project. CI scans only `final-devops-project/` (files) and
`--log-opts="--all -- final-devops-project .github/workflows/session21-final.yml"` (history).
`.gitleaks.toml` skips generated files (lockfile, node_modules, dist, .terraform) and allowlists
exactly one value. My final scan of the finished folder found 7 hits of rule `curl-auth-user`: the
`curl -u admin:demo-admin-123` commands I ran against the local Grafana (in `outputs/14-grafana.txt`
and this README). That password is the fake value from the monitoring values file, but the CI gate
would have blocked the push on it. I allowlisted that exact value (not the rule, not the files) and
checked that the same `-u user:password` pattern with any other (made-up) password is still caught:

```
$ gitleaks dir . --config security/.gitleaks.toml --redact --no-banner -v
1:30AM INF no leaks found
$ (a test file with the same curl line but another, made-up password, built at run time) && gitleaks dir ...
leaks found: 1
```

All passwords in this project are fake demo values (`demo-password-123`, `demo-admin-123`) and say so
where they appear.

**Trivy image results, explained** (`outputs/06-trivy-image.txt`):

```
backend (all severities):
HIGH	total=44	fixable=0
LOW	total=61	fixable=0
MEDIUM	total=58	fixable=0
UNKNOWN	total=2	fixable=0
$ trivy image --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 taskboard-backend:local; echo gate-exit=$?
│ taskboard-backend:local (debian 13.7) │ debian │ 0 │
gate-exit=0
$ jq ... 'CVE-2025-69720' security/reports/trivy-backend.json
CVE-2025-69720
HIGH
ncurses: ncurses: Buffer overflow vulnerability may lead to arbitrary code execution.
affected
```

All 165 backend findings are in Debian base packages and have **no fixed version** yet (status
"affected"); every Python package is at 0. Example: CVE-2025-69720 is a buffer overflow in ncurses
(`libncursesw6`, `libtinfo6`, `ncurses-bin`). My app never calls ncurses (no terminal UI, no shell in
normal operation), and there is no patched Debian package to move to, so `--ignore-unfixed` is the
right gate: it fails the build the moment a fix exists and I have not picked it up. Python's own
dependencies and pip are where fixes *do* exist, which is why pip is removed from the image.

The frontend image had 1 MEDIUM (zlib CVE-2026-85091, fix in 1.3.2-r1). I added `apk upgrade` to the
runtime stage. That first failed because this Mac's Docker briefly could not resolve
`dl-cdn.alpinelinux.org` (transcript shows the `bad address` error and my temporary revert); when DNS
was back I re-added it and the frontend image went to **0 vulnerabilities of any severity**:

```
$ trivy image --scanners vuln --format json -o security/reports/trivy-frontend.json --quiet taskboard-frontend:local && jq '[.Results[].Vulnerabilities[]?] | length' security/reports/trivy-frontend.json
0
```

**IaC misconfiguration scan** (`outputs/25-iac-misconfig-scan.txt`): Trivy config found, among others,
`AWS-0040 (CRITICAL): Public cluster access is enabled`, `AWS-0041 (CRITICAL): Cluster allows access
from a public CIDR: 0.0.0.0/0`, `AWS-0039 (HIGH): Cluster does not have secret encryption enabled`,
`AWS-0164 (HIGH): Subnet associates public IP address` and `KSV-0014 (HIGH)` (postgres without
read-only root FS). I fixed those five kinds of finding (private EKS endpoint by default, KMS
encryption of Secrets, no auto public IPs, read-only postgres root FS with emptyDirs) and accepted two
in `security/.trivyignore` with written reasons: node egress to 0.0.0.0/0 (nodes must pull from
public registries) and SSE-S3 instead of a customer-managed KMS key for a non-sensitive bucket.
After the change: every target `0`, gate exit 0. The read-only postgres was rolled out and checked:

```
$ kubectl -n taskboard exec deploy/taskboard-postgres -- sh -c 'touch /should-fail 2>&1; id'
touch: /should-fail: Read-only file system
uid=70(postgres) gid=70(postgres) groups=70(postgres)
```

---

## 14. Monitoring and logs

kube-prometheus-stack 92.1.0 from its OCI registry, trimmed for a shared 8 GB Docker VM
(`monitoring/kube-prometheus-stack-values.yaml`). The chart's ServiceMonitor scrapes the backend's
`http` port at `/metrics` every 15 s; the PrometheusRule adds 3 alerts.

```
$ curl -s 'http://localhost:30112/api/v1/targets?state=active' | jq -r '... select(.labels.namespace=="taskboard") ...'
serviceMonitor/taskboard/taskboard-backend/0  taskboard-backend-59d5dcc795-4r2g9  http://10.244.0.16:8000/metrics  health=up  lastError=
serviceMonitor/taskboard/taskboard-backend/0  taskboard-backend-59d5dcc795-865pz  http://10.244.0.17:8000/metrics  health=up  lastError=
serviceMonitor/taskboard/taskboard-backend/0  taskboard-backend-59d5dcc795-hjxm7  http://10.244.0.49:8000/metrics  health=up  lastError=
serviceMonitor/taskboard/taskboard-backend/0  taskboard-backend-59d5dcc795-wsgk6  http://10.244.0.50:8000/metrics  health=up  lastError=
```

PromQL through the Prometheus HTTP API (`outputs/13-prometheus-promql.txt`, label noise removed):

| Query | Result |
|---|---|
| `up{namespace="taskboard"}` | 4 pods => `1` (HPA had 4 replicas at that moment) |
| `sum(rate(http_requests_total{namespace="taskboard"}[2m]))` | `370.1` req/s during the load |
| `sum by (status) (rate(http_requests_total[5m]))` | 200 => `175.87`, 201 => `0.110`, 404 => `0.112` |
| `histogram_quantile(0.95, sum by (le) (rate(http_request_duration_seconds_bucket[5m])))` | `0.095` s |
| `sum by (action) (taskboard_task_events_total)` | created `73`, updated `1`, deleted `1` |
| `sum by (pod) (rate(container_cpu_usage_seconds_total{container="backend"}[2m]))` | 0.249 / 0.239 / 0.135 / 0.127 cores |
| `kube_horizontalpodautoscaler_status_current_replicas` | `4` |

Alert rules loaded: `TaskboardBackendDown`, `TaskboardHighErrorRate`, `TaskboardHighLatencyP95`, all
`health=ok`. `TaskboardBackendDown` really fired during troubleshooting case 3:

```
00:53:03 TaskboardBackendDown=pending
00:54:03 TaskboardBackendDown=firing
{"state":"firing","activeAt":"2026-10-07T19:22:57.566628837Z","severity":"critical","summary":"No TaskBoard backend target is up in taskboard"}
...after the fix:
01:00:00 TaskboardBackendDown=inactive
```

Grafana (`outputs/14-grafana.txt`):

```
$ curl -s http://localhost:30111/api/health
{ "database": "ok", "version": "13.2.3", ... }
$ curl -s -u admin:demo-admin-123 http://localhost:30111/api/datasources/uid/prometheus/health | jq -c .
{"details":{"application":"Prometheus",...},"message":"Successfully queried the Prometheus API.","status":"OK"}
$ curl -s -u admin:demo-admin-123 'http://localhost:30111/api/search?query=TaskBoard' | jq -r ...
TaskBoard - API overview  uid=taskboard-overview  url=/d/taskboard-overview/taskboard-api-overview
$ curl -s -u admin:demo-admin-123 -X POST http://localhost:30111/api/ds/query ... 'sum(rate(http_requests_total{namespace="taskboard"}[1m]))' ...
[[1791400314130],[229.39733048901527]]
```

![Grafana dashboard](outputs/screenshots/04-grafana-dashboard.png)

**What I observed:**
- New ServiceMonitor -> first scrape took about 2.5 minutes: the operator rewrites the config Secret,
  the kubelet syncs the mounted Secret, then the config-reloader reloads Prometheus.
- Grafana was **OOMKilled** (exit 137) at a 256Mi limit as soon as I opened the dashboard in a browser.
  Raised to 512Mi; stable since.
- The "5xx ratio" panel showed "No data": with zero 5xx responses there is no 5xx series, and an empty
  vector divided by anything is empty. `or vector(0)` fixed it.

Logs (`outputs/23-logs.txt`): one POST followed through ingress-nginx (`"POST /api/tasks HTTP/1.1" 201
... [taskboard-taskboard-backend-http] ... 10.244.0.66:8000`), the backend's own log line
(`INFO taskboard task created id=75 priority=HIGH`), postgres checkpoints, the `migrate`
initContainer of a restarted pod (no "Running upgrade" lines: already at head, so the migration is
idempotent), and the namespace events.

---

## 15. GitOps

`gitops/argocd-application.yaml` is the real Application: repo
`https://github.com/rudhar07/devops-heros.git`, `targetRevision: main`, path
`final-devops-project/helm/taskboard`, values `values-gitops.yaml`, automated sync with `prune` and
`selfHeal`. That path exists only after the push, so for the live demo I served a scratch copy of the
same layout from a `git daemon` container (`hw-f-gitd`) on the docker `kind` network and pointed an
otherwise identical Application at `git://hw-f-gitd/final-gitops-repo`
(`gitops/argocd-application-local-demo.yaml`; local images instead of GHCR). ArgoCD 3.5.4, non-HA,
with dex/notifications/applicationset scaled to 0.

Initial sync (`outputs/22-gitops.txt`):

```
01:09:58 Synced/Progressing
01:10:23 Synced/Healthy
$ argocd app get taskboard-gitops --grpc-web
Sync Status:        Synced to main (891df0c)
Health Status:      Healthy
$ curl -s http://gitops.localhost:30110/api/info
{"service":"TaskBoard API","version":"2.0.0","environment":"gitops-v1","commit":"local","docs":"/docs"}
```

**A change in Git becomes a deployment** (edit `values-gitops.yaml`: `appEnv gitops-v1 -> gitops-v2`,
frontend replicas `1 -> 2`, commit; no kubectl, no helm):

```
-  replicaCount: 1
+  replicaCount: 2
-  appEnv: gitops-v1
+  appEnv: gitops-v2
d5889ef gitops: appEnv gitops-v2, frontend 2 replicas
$ argocd app get taskboard-gitops --refresh --grpc-web | grep -E 'Sync Status|Health Status'
Sync Status:        OutOfSync from main (d5889ef)
01:10:39 revision=d5889ef OutOfSync/Healthy api.environment=gitops-v1
01:10:44 revision=d5889ef Synced/Progressing api.environment=gitops-v1
01:10:54 revision=d5889ef Synced/Healthy api.environment=gitops-v2
taskboard-gitops-frontend   2/2     2            2           58s
```

**Drift is healed** (scale the frontend to 4 and set LOG_LEVEL=DEBUG by hand):

```
$ kubectl -n taskboard-gitops scale deploy taskboard-gitops-frontend --replicas=4
$ kubectl -n taskboard-gitops patch configmap taskboard-gitops-config --type merge -p '{"data":{"LOG_LEVEL":"DEBUG"}}'
01:11:05 frontend.spec.replicas=4 LOG_LEVEL=DEBUG app=Synced
01:11:07 frontend.spec.replicas=2 LOG_LEVEL=INFO app=Synced
2026-10-07T19:41:05Z  Applying resource ConfigMap/taskboard-gitops-config in cluster: https://10.96.0.1:443, namespace: taskboard-gitops
2026-10-07T19:41:05Z  Applying resource Deployment/taskboard-gitops-frontend in cluster: https://10.96.0.1:443, namespace: taskboard-gitops
2026-10-07T19:41:05Z  Partial sync operation to d5889ef011fa82e6632b68ab8de2149598f58336 succeeded
```

**What I observed:** the ConfigMap change rolled the backend too, because the chart puts a checksum
of the ConfigMap into the pod annotations. ArgoCD only polls Git every 3 minutes, so I triggered a
refresh; a GitHub webhook would do the same on the real repo. Self-heal took ~2 seconds and re-applied
only the two drifted objects, not the whole app. The first git-daemon container failed because
`apk add` hit the same flaky Alpine CDN; a retry loop fixed it.

---

## 16. Troubleshooting challenge

Six faults across six layers, plus the instructor's two broken manifests. Each: break -> identify ->
investigate -> root cause -> fix -> verify. Files in `troubleshooting/`, summary table in
`troubleshooting/README.md`.

### Case 1 - wrong DB host in the ConfigMap (config) - `outputs/15-tshoot-case1-db-host.txt`

```
BEFORE  $ kubectl -n taskboard get cm taskboard-config -o jsonpath='{.data.DB_HOST}'
        taskboard-postgres
BREAK   $ helm upgrade ... -f troubleshooting/case1-wrong-db-host.values.yaml --wait --timeout 90s
        Error: UPGRADE FAILED: resource Deployment/taskboard/taskboard-backend not ready. status: InProgress, message: Updated: 1/2
        taskboard-backend-77fd84c58-6dmf5    0/1     Init:0/2   0          90s
INVEST. $ kubectl -n taskboard logs $NEW -c wait-for-db --tail 4
        taskboard-postgress:5432 - no response
        waiting for taskboard-postgress:5432 (44)
        ** server can't find taskboard-postgress.taskboard.svc.cluster.local: NXDOMAIN
        API through Ingress during the incident: HTTP 200
FIX     $ helm rollback taskboard 0 -n taskboard --wait --timeout 3m
AFTER   taskboard-postgres ... deployment "taskboard-backend" successfully rolled out
```

Root cause: a typo (`taskboard-postgress`) in `database.host` became `DB_HOST` in the ConfigMap; the
name does not resolve, so the new pod never got past `wait-for-db`. Users saw nothing: with 2 replicas
`maxUnavailable` rounds to 0 and the new pod never became Ready, so the old ReplicaSet kept serving.
The initContainer turned a would-be CrashLoop into a clear, readable wait message.

### Case 2 - image tag that does not exist (image/registry) - `outputs/16-tshoot-case2-image.txt`

```
$ kubectl -n taskboard get pods -l app.kubernetes.io/component=backend
taskboard-backend-846c6d8b6d-p77rw   0/1     Init:ImagePullBackOff   0          45s
Warning  Failed  ... Failed to pull image "taskboard-backend:v2.0.1-typo": ... "docker.io/library/taskboard-backend:v2.0.1-typo": pull access denied, repository does not exist or may require authorization
$ docker exec hw-f-control-plane crictl images | grep -E 'IMAGE|taskboard-backend'
docker.io/library/taskboard-backend                      local                ae87e1dd05590       65.6MB
$ helm rollback taskboard 0 -n taskboard --wait --timeout 3m
taskboard-backend:local
```

Root cause: `backend.image.tag=v2.0.1-typo` was never built. The node only has `:local`, so the
kubelet tried Docker Hub (`docker.io/library/...`, the default for an unqualified name) and was
refused. Note it fails in the **init** container `migrate` first, because that uses the same image.
The instructor's `broken-image.yaml` fails the same way for a different reason
(`ghcr.io/example/taskboard-backend:does-not-exist`, `403 Forbidden` on the token request); I deleted it.

### Case 3 - Service selector does not match (service) - `outputs/17-tshoot-case3-service-selector.txt`

```
$ kubectl -n taskboard patch svc taskboard-backend --type=json -p "$(cat troubleshooting/case3-service-selector.patch.json)"
00:52:33 /api/tasks -> 503            (UI still 200, all backend pods 1/1 Running)
$ kubectl -n taskboard get endpointslices -l kubernetes.io/service-name=taskboard-backend
taskboard-backend-tkvg4   IPv4          <unset>   <unset>     39m
$ kubectl -n taskboard get svc taskboard-backend -o jsonpath='{.spec.selector}'
{"app.kubernetes.io/component":"api","app.kubernetes.io/instance":"taskboard","app.kubernetes.io/name":"taskboard"}
W1007 19:22:32.586491  ... Service "taskboard/taskboard-backend" does not have any active Endpoint.
00:54:03 TaskboardBackendDown=firing
```

Root cause: the selector asked for `component=api`, the pods are `component=backend`, so 0 endpoints
and ingress-nginx answers 503. Monitoring noticed too: Prometheus discovers targets through the
Service endpoints, so the targets vanished and my `absent(up{...})` alert fired.

The first fix attempt failed, which taught me something about Helm 4:

```
$ helm upgrade taskboard helm/taskboard -n taskboard -f helm/taskboard/values-dev.yaml --wait --timeout 3m
Error: UPGRADE FAILED: conflict occurred while applying object taskboard/taskboard-backend /v1, Kind=Service: Apply failed with 1 conflict: conflict with "kubectl-patch" using v1: .spec.selector
$ kubectl -n taskboard get svc taskboard-backend --show-managed-fields -o json | jq ...
helm  Apply  owns selector: false
kubectl-patch  Update  owns selector: true
$ helm upgrade ... --force-conflicts --wait --timeout 3m
STATUS: deployed
{"app.kubernetes.io/component":"backend",...}
taskboard-backend-tkvg4   IPv4          8000    10.244.0.16,10.244.0.17   47m
00:59:50 /api/tasks -> 200
01:00:00 TaskboardBackendDown=inactive
```

Helm 4 uses server-side apply; my `kubectl patch` became the owner of `.spec.selector`, so Helm
refuses to overwrite it unless told to (`--force-conflicts`). Helm 3's three-way merge would have
silently overwritten it. The instructor's `broken-service.yaml` shows the same lesson: selector
`app=label-that-does-not-exist`, endpoints `<unset>`.

### Case 4 - Ingress to the wrong Service and port (routing) - `outputs/18-tshoot-case4-ingress.txt`

This is exactly the bug in the instructor's chart (`/api` -> `taskboard-backend:8080` while the
Service listens on 8000), plus a second mistake (a Service name that does not exist):

```
/api/tasks -> HTTP 503
/          -> HTTP 503
$ kubectl -n taskboard describe ingress taskboard-broken | sed -n '/Rules/,/Annotations/p'
                    /api   taskboard-backend:8080 ()
                    /      taskboard-frontend-v2:80 (<error: services "taskboard-frontend-v2" not found>)
$ kubectl -n taskboard get svc taskboard-backend -o jsonpath='{.spec.ports}'
[{"name":"http","port":8000,"protocol":"TCP","targetPort":"http"}]
...patched to the named port "http" and the real Service:
                    /api   taskboard-backend:http (10.244.0.16:8000,10.244.0.17:8000)
                    /      taskboard-frontend:http (10.244.0.57:8080,10.244.0.58:8080)
/api/tasks -> 200
/ -> HTTP 200
```

The empty `()` after `taskboard-backend:8080` is the clue: describe shows the endpoints it resolved,
and for a port the Service does not have it resolves none. Using the **named** port (`http`) in the
Ingress, as my chart does, means a port-number change in the Service cannot break routing.

### Case 5 - liveness probe on a wrong path (probes) - `outputs/19-tshoot-case5-probe.txt`

```
taskboard-backend-5bcf44557b-bmvc4   0/1     CrashLoopBackOff   3 (14s ago)   75s
taskboard-backend-5bcf44557b-bzps6   0/1     CrashLoopBackOff   3 (19s ago)   65s
    Liveness:   http-get http://:http/healthz delay=5s timeout=3s period=5s #success=1 #failure=2
INFO:     10.244.0.1:59562 - "GET /healthz HTTP/1.1" 404 Not Found
INFO:     Shutting down
$ helm rollback taskboard 0 -n taskboard --wait --timeout 3m
/health
taskboard-backend-59d5dcc795-dmqvg   1/1     Running   0          50s
```

Root cause: `/healthz` is the **nginx** health path; FastAPI serves `/health`, so every liveness check
got 404 and the kubelet restarted the container after 2 failures. This was the worst case of the six:
readiness (`/ready`) was fine, so the new pods became Ready, the rollout replaced **both** old pods,
and only then did liveness start killing them. Both replicas ended in CrashLoopBackOff: a full outage.
A bad image or bad config is stopped by the rolling update; a bad liveness probe is not. (My two
`kubectl exec` checks in the transcript failed with `container not found`, because the container was
in back-off at that moment; the logs above already proved the 404.)

### Case 6 - HPA without CPU requests (autoscaling) - `outputs/20-tshoot-case6-hpa.txt`

```
hpa-demo   Deployment/hpa-demo   cpu: <unknown>/50%   1         3         1          60s
  ScalingActive  False   FailedGetResourceMetric  the HPA was unable to compute the replica count: failed to get cpu utilization: missing request for cpu in container web of Pod hpa-demo-5446ff5b55-g46n6
$ kubectl -n taskboard get deploy hpa-demo -o jsonpath='{.spec.template.spec.containers[0].resources}'
{}
$ kubectl apply -f troubleshooting/case6-hpa-fixed.yaml
01:04:52 utilisation=30
hpa-demo   Deployment/hpa-demo   cpu: 30%/50%   1         3         1          92s
  ScalingActive   True    ValidMetricFound    the HPA was able to successfully calculate a replica count from cpu resource utilization (percentage of request)
```

Root cause: utilisation is usage divided by the **request**; without a request there is nothing to
divide by, even though `kubectl top` has the usage. Fix: add `resources.requests`.

---

## 17. Lessons learned

1. **Readiness protects you from bad config and bad images, not from a bad liveness probe.** Cases 1
   and 2 caused no user-visible error because new pods never became Ready. Case 5 passed readiness and
   then killed every replica. Liveness should be cheap and must point at the right container's path.
2. **Know who owns a field.** Helm 4's server-side apply refused to overwrite a field that
   `kubectl patch` had taken over. In a GitOps setup the same rule holds: hand edits are drift, and
   ArgoCD's selfHeal (2 s here) is the automatic version of `--force-conflicts`.
3. **"Ready" has layers.** Pods Ready -> EndpointSlice updated -> ingress-nginx reloaded -> Prometheus
   discovered the target. I saw 2 s of 503 after "Available" and 2.5 min before the first scrape.
4. **An emulator is not the cloud.** LocalStack community has no EKS/ECR and reports SG references
   differently (permanent 3-change plan). I checked the gaps with the AWS CLI and wrote them down
   instead of pretending the EKS part was applied.
5. **Scanners are only useful with a policy.** 165 backend CVEs sounds bad; 0 of them have a fix. The
   gate (`HIGH,CRITICAL`, `--ignore-unfixed`) fails on what I can act on, and the IaC scan made me fix
   real design issues (public EKS endpoint, unencrypted Secrets).
6. **Size limits for real.** Grafana OOMKilled at 256Mi only when a human opened a dashboard; the
   pod looked fine until then.
7. **Small tooling details cost the most time:** kind + containerd multi-platform images,
   `pg_isready` as a UID without a passwd entry, `kubectl run --overrides` replacing the command, a
   flaky package CDN. Each is now written down next to the fix.

---

## 18. Grading rubric mapping

The rubric (`session21-python/GRADING.md`) expects `backend/`, `frontend/`, `k8s/` at the project root;
the required structure for this homework puts them under `application/` and `kubernetes/`, so paths
below use that layout.

| Module | Criterion | Where / evidence |
|---|---|---|
| **M1 Application (10)** | FastAPI starts, `/health` | `application/backend/app/main.py`; `outputs/04` (`{"status":"UP"}`) |
| | ≥ 4 REST endpoints GET/POST/PUT/DELETE | section 6 table; `outputs/04`, `09` |
| | PostgreSQL table via Alembic | `alembic/versions/0001_*.py`, `0002_*.py`; `outputs/03`, `04` (`alembic_version = 0002_due_date_updated_at`) |
| | React frontend renders, calls API | `application/frontend/src/`; screenshots 01, 02 |
| | Responsive, usable UI | screenshot 03 (390 px) |
| **M2 Testing (10)** | pytest runs | `outputs/01` (24 passed) |
| | ≥ 5 tests, ≥ 3 endpoints | 24 tests covering every endpoint |
| | test DB, not production | `tests/conftest.py` (in-memory SQLite, dependency override) |
| | `pytest.ini`/`conftest.py` | both present |
| **M3 Git (5)** | public repo | github.com/rudhar07/devops-heros (public fork) |
| | meaningful commit messages, ≥ 10 commits | the student's own commits (see the suggested message in the hand-off) |
| | `.gitignore` excludes .env, `__pycache__`, node_modules, .venv | root `.gitignore` + `final-devops-project/.gitignore` (.env, coverage, reports) |
| **M4 Docker (10)** | backend Dockerfile builds | `outputs/02` |
| | frontend multi-stage (Node -> Nginx) | `application/frontend/Dockerfile` |
| | non-root | UID 10001 / UID 101, `outputs/02` |
| | `docker compose up --build` starts all 3 | `outputs/03` (+ migrate one-shot) |
| **M5 CI/CD (15)** | workflow in `.github/workflows/` | repo-root `session21-final.yml` |
| | triggers on push to main | `on.push.branches: [main]` + paths |
| | pytest job fails the build | `backend-test` (`--cov-fail-under=80`) |
| | frontend built | `frontend-build` |
| | both images built | `docker-build` matrix |
| | pushed to GHCR | `push-images` (GITHUB_TOKEN, `packages: write`, main only) |
| | SHA tags, not latest | `:${GITHUB_SHA}` (+ `:2.0.0`), no `latest` |
| **M6 Trivy (5)** | Trivy on both images in CI | `image-scan` matrix |
| | fails on HIGH/CRITICAL | `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` |
| | explain a CVE / clean result | section 13 (CVE-2025-69720, zlib fix) |
| **M7 Terraform (15)** | valid HCL | `terraform validate` -> Success |
| | init OK | `outputs/24` |
| | non-empty plan | 35 (LocalStack) / 42 (full AWS design) |
| | VPC + ≥ 2 public subnets | applied on LocalStack, verified with AWS CLI |
| | EKS + node group | in code and in the plan; **not applied** (LocalStack community has no EKS; no AWS account) |
| | destroy cleanly | `Destroy complete! Resources: 35 destroyed.` |
| | `terraform.tfvars.example`, no creds | present; provider uses fake `test` creds only for LocalStack |
| **M8 Kubernetes + Helm (15)** | namespace yaml applies | `kubernetes/00-namespace.yaml`, `outputs/11` |
| | chart with Chart.yaml, values, templates | `helm/taskboard/` |
| | `helm upgrade --install` works | `outputs/08`, `09` |
| | ≥ 2 replicas backend and frontend | `outputs/27` (2/2 each) |
| | ClusterIP Services | `outputs/09`, `27` |
| | Ingress `/` -> frontend, `/api` -> backend | `outputs/09`, screenshot 02 |
| | all pods Running | `outputs/27` |
| **M9 Observability (10)** | `/metrics` Prometheus format | `outputs/04` |
| | Prometheus scraping the app | `outputs/13` (targets `health=up`) |
| | Grafana accessible | `outputs/14` |
| | panel with live app metrics | screenshot 04 |
| **M10 Docs + demo (5)** | README explains the app | this file |
| | live demo commit -> pipeline -> deployment | GitOps demo (section 15); the GitHub run link after the push |

## 19. Honest notes: what differs from the spec

- **GitHub Actions run:** not run yet (it starts with the push). Everything it runs was run locally
  with the same tool versions and config files, the workflow is actionlint/shellcheck clean, and the
  compose-e2e job was rehearsed command by command. The run link placeholder is in section 12.
- **AWS:** LocalStack instead of real AWS. EKS, the node group, the EKS KMS key and ECR are in the code
  and in `terraform plan`, but were not applied (not emulated by LocalStack community). Real-AWS
  differences are listed in section 11.
- **GitOps:** live demo against a local git daemon serving a scratch copy of the same folder layout,
  with local images. The GitHub Application file is ready for after the push.
- **Kubernetes:** kind on a laptop instead of EKS; `*.localhost` hosts instead of real DNS and TLS.
- **Screenshots:** text transcripts plus four real browser screenshots; no screenshot of the GitHub
  UI or the AWS console exists yet.
- **App domain:** GRADING.md asks for an own domain beyond the reference TaskBoard. The homework
  instructions for this folder fixed the chart path `helm/taskboard`, so I kept the TaskBoard name
  and extended it (section 1 table) instead of renaming it.
