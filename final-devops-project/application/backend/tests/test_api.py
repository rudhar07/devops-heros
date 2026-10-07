from datetime import date, timedelta

from sqlalchemy.exc import OperationalError

from app.db import get_db
from app.main import app


# ---------------------------------------------------------------- platform
def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "UP"}


def test_root_shows_service_and_version(client):
    body = client.get("/").json()
    assert body["service"] == "TaskBoard API"
    assert body["environment"] == "test"
    assert "commit" in body


def test_api_info_matches_root(client):
    assert client.get("/api/info").json() == client.get("/").json()


def test_ready_when_database_answers(client):
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "READY"}


def test_ready_returns_503_when_database_is_down(client):
    class BrokenSession:
        def execute(self, *_args, **_kwargs):
            raise OperationalError("SELECT 1", {}, Exception("connection refused"))

    app.dependency_overrides[get_db] = lambda: BrokenSession()
    response = client.get("/ready")
    assert response.status_code == 503
    assert response.json()["status"] == "NOT_READY"


def test_metrics_endpoint_exposes_prometheus_format(client, make_task):
    make_task()
    client.get("/api/tasks")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    text = response.text
    assert "http_requests_total" in text
    assert 'taskboard_task_events_total{action="created"}' in text


# ------------------------------------------------------------------ create
def test_create_task_returns_201_and_defaults(client):
    response = client.post("/api/tasks", json={"title": "Deploy application"})
    assert response.status_code == 201
    body = response.json()
    assert body["id"] > 0
    assert body["status"] == "TODO"
    assert body["priority"] == "MEDIUM"
    assert body["assignee"] == "Unassigned"
    assert body["due_date"] is None


def test_create_task_rejects_empty_title(client):
    response = client.post("/api/tasks", json={"title": ""})
    assert response.status_code == 422


def test_create_task_rejects_unknown_priority(client):
    response = client.post("/api/tasks", json={"title": "x", "priority": "URGENT"})
    assert response.status_code == 422


# -------------------------------------------------------------------- read
def test_list_tasks_newest_first(client, make_task):
    first = make_task(title="first")
    second = make_task(title="second")
    ids = [t["id"] for t in client.get("/api/tasks").json()]
    assert ids == [second["id"], first["id"]]


def test_list_tasks_filters_by_status_and_priority(client, make_task):
    make_task(title="a", status="DONE", priority="LOW")
    make_task(title="b", status="TODO", priority="HIGH")
    make_task(title="c", status="TODO", priority="LOW")
    todo = client.get("/api/tasks", params={"status": "TODO"}).json()
    assert {t["title"] for t in todo} == {"b", "c"}
    todo_low = client.get("/api/tasks", params={"status": "TODO", "priority": "LOW"}).json()
    assert [t["title"] for t in todo_low] == ["c"]


def test_list_tasks_search_and_paging(client, make_task):
    make_task(title="Configure Ingress", assignee="Asha")
    make_task(title="Write tests", description="cover the ingress path")
    make_task(title="Unrelated")
    found = client.get("/api/tasks", params={"q": "INGRESS"}).json()
    assert len(found) == 2
    page = client.get("/api/tasks", params={"limit": 1, "offset": 1}).json()
    assert len(page) == 1
    assert client.get("/api/tasks", params={"limit": 0}).status_code == 422


def test_get_single_task(client, make_task):
    task = make_task(title="Read me")
    response = client.get(f"/api/tasks/{task['id']}")
    assert response.status_code == 200
    assert response.json()["title"] == "Read me"


def test_get_missing_task_returns_404(client):
    response = client.get("/api/tasks/9999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Task not found"


# ------------------------------------------------------------------ update
def test_update_task_changes_only_sent_fields(client, make_task):
    task = make_task(title="Old title", description="keep me")
    response = client.put(f"/api/tasks/{task['id']}", json={"title": "New title", "status": "IN_PROGRESS"})
    assert response.status_code == 200
    body = response.json()
    assert body["title"] == "New title"
    assert body["status"] == "IN_PROGRESS"
    assert body["description"] == "keep me"


def test_update_rejects_invalid_status(client, make_task):
    task = make_task()
    assert client.put(f"/api/tasks/{task['id']}", json={"status": "BLOCKED"}).status_code == 422


def test_update_missing_task_returns_404(client):
    assert client.put("/api/tasks/9999", json={"title": "x"}).status_code == 404


# ------------------------------------------------------------------ delete
def test_delete_task(client, make_task):
    task = make_task()
    response = client.delete(f"/api/tasks/{task['id']}")
    assert response.status_code == 204
    assert response.content == b""
    assert client.get(f"/api/tasks/{task['id']}").status_code == 404


def test_delete_missing_task_returns_404(client):
    assert client.delete("/api/tasks/9999").status_code == 404


# ------------------------------------------------------------------- stats
def test_stats_counts_by_status_priority_and_overdue(client, make_task):
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    tomorrow = (date.today() + timedelta(days=1)).isoformat()
    make_task(status="TODO", priority="HIGH", due_date=yesterday)   # open, high, overdue
    make_task(status="IN_PROGRESS", priority="LOW", due_date=tomorrow)
    make_task(status="DONE", priority="HIGH", due_date=yesterday)   # done: not overdue, not open
    stats = client.get("/api/tasks/stats").json()
    assert stats == {"total": 3, "todo": 1, "inProgress": 1, "done": 1, "highPriorityOpen": 1, "overdue": 1}


def test_stats_on_empty_board(client):
    assert client.get("/api/tasks/stats").json()["total"] == 0
