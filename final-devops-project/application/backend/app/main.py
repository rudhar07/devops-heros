import logging
from contextlib import asynccontextmanager
from datetime import date

from fastapi import Depends, FastAPI, HTTPException, Query, Response, status
from fastapi.responses import JSONResponse
from prometheus_fastapi_instrumentator import Instrumentator
from sqlalchemy import func, or_, select, text
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from .config import settings
from .db import get_db
from .metrics import TASK_EVENTS
from .models import Task
from .schemas import Priority, StatsOut, Status, TaskCreate, TaskOut, TaskUpdate

logging.basicConfig(
    level=settings.log_level.upper(),
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
log = logging.getLogger("taskboard")


@asynccontextmanager
async def lifespan(_app: FastAPI):
    # The schema is created by Alembic (Kubernetes initContainer / Compose
    # "migrate" service), never by the app itself.
    log.info("starting %s %s env=%s commit=%s", settings.app_name, settings.app_version, settings.app_env, settings.git_sha)
    yield
    log.info("shutting down")


app = FastAPI(title=settings.app_name, version=settings.app_version, lifespan=lifespan)

# /metrics in Prometheus text format: http_requests_total,
# http_request_duration_seconds, ... plus the taskboard_* business metrics.
Instrumentator(
    should_group_status_codes=False,
    excluded_handlers=["/metrics", "/health", "/ready"],
).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)


def get_task_or_404(task_id: int, db: Session) -> Task:
    task = db.get(Task, task_id)
    if task is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Task not found")
    return task


def service_info() -> dict:
    return {
        "service": settings.app_name,
        "version": settings.app_version,
        "environment": settings.app_env,
        "commit": settings.git_sha,
        "docs": "/docs",
    }


@app.get("/")
def root():
    return service_info()


@app.get("/api/info")
def api_info():
    """Same as / but under /api, so the browser can read it through the proxy/Ingress."""
    return service_info()


@app.get("/health")
def health():
    """Liveness: the process is up. Deliberately does not touch the database."""
    return {"status": "UP"}


@app.get("/ready")
def ready(db: Session = Depends(get_db)):
    """Readiness: only send traffic here if PostgreSQL answers."""
    try:
        db.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        log.warning("readiness check failed: %s", exc.__class__.__name__)
        return JSONResponse(status_code=503, content={"status": "NOT_READY", "reason": "database unavailable"})
    return {"status": "READY"}


@app.get("/api/tasks", response_model=list[TaskOut])
def list_tasks(
    task_status: Status | None = Query(default=None, alias="status"),
    priority: Priority | None = None,
    q: str | None = Query(default=None, max_length=100, description="Search in title, description and assignee"),
    limit: int = Query(default=100, ge=1, le=500),
    offset: int = Query(default=0, ge=0),
    db: Session = Depends(get_db),
):
    stmt = select(Task)
    if task_status:
        stmt = stmt.where(Task.status == task_status)
    if priority:
        stmt = stmt.where(Task.priority == priority)
    if q:
        pattern = f"%{q.lower()}%"
        stmt = stmt.where(
            or_(
                func.lower(Task.title).like(pattern),
                func.lower(Task.description).like(pattern),
                func.lower(Task.assignee).like(pattern),
            )
        )
    stmt = stmt.order_by(Task.id.desc()).limit(limit).offset(offset)
    return list(db.scalars(stmt))


@app.get("/api/tasks/stats", response_model=StatsOut)
def stats(db: Session = Depends(get_db)):
    rows = db.execute(select(Task.status, func.count(Task.id)).group_by(Task.status)).all()
    counts = {row_status: count for row_status, count in rows}
    high_open = db.scalar(
        select(func.count(Task.id)).where(Task.priority == "HIGH", Task.status != "DONE")
    )
    overdue = db.scalar(
        select(func.count(Task.id)).where(Task.due_date < date.today(), Task.status != "DONE")
    )
    return StatsOut(
        total=sum(counts.values()),
        todo=counts.get("TODO", 0),
        inProgress=counts.get("IN_PROGRESS", 0),
        done=counts.get("DONE", 0),
        highPriorityOpen=high_open or 0,
        overdue=overdue or 0,
    )


@app.get("/api/tasks/{task_id}", response_model=TaskOut)
def get_task(task_id: int, db: Session = Depends(get_db)):
    return get_task_or_404(task_id, db)


@app.post("/api/tasks", response_model=TaskOut, status_code=status.HTTP_201_CREATED)
def create_task(payload: TaskCreate, db: Session = Depends(get_db)):
    task = Task(**payload.model_dump())
    db.add(task)
    db.commit()
    db.refresh(task)
    TASK_EVENTS.labels(action="created").inc()
    log.info("task created id=%s priority=%s", task.id, task.priority)
    return task


@app.put("/api/tasks/{task_id}", response_model=TaskOut)
def update_task(task_id: int, payload: TaskUpdate, db: Session = Depends(get_db)):
    task = get_task_or_404(task_id, db)
    for key, value in payload.model_dump(exclude_unset=True).items():
        setattr(task, key, value)
    db.commit()
    db.refresh(task)
    TASK_EVENTS.labels(action="updated").inc()
    log.info("task updated id=%s status=%s", task.id, task.status)
    return task


@app.delete("/api/tasks/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, db: Session = Depends(get_db)):
    task = get_task_or_404(task_id, db)
    db.delete(task)
    db.commit()
    TASK_EVENTS.labels(action="deleted").inc()
    log.info("task deleted id=%s", task_id)
    return Response(status_code=status.HTTP_204_NO_CONTENT)
