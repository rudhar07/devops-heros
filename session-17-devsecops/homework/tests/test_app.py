import pytest

from app.app import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


# ── Tests 1-8: the instructor's original tests (demo/tests/test_app.py) ──

def test_home(client):
    response = client.get("/")
    assert response.status_code == 200


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json()["status"] == "healthy"


def test_greet(client):
    response = client.get("/api/greet/Rudhar")
    assert response.status_code == 200
    assert "Rudhar" in response.get_json()["message"]


def test_add_numbers(client):
    response = client.post("/api/add", json={"number1": 10, "number2": 20})
    assert response.status_code == 200
    assert response.get_json()["result"] == 30


def test_add_numbers_missing_fields(client):
    response = client.post("/api/add", json={"number1": 5})
    assert response.status_code == 400


def test_calculator_multiply(client):
    response = client.post("/api/calculate", json={"a": 4, "b": 5, "operation": "multiply"})
    assert response.status_code == 200
    assert response.get_json()["result"] == 20


def test_calculator_divide_by_zero(client):
    response = client.post("/api/calculate", json={"a": 10, "b": 0, "operation": "divide"})
    assert response.status_code == 400


def test_status(client, monkeypatch):
    monkeypatch.setenv("GIT_SHA", "abc123")
    response = client.get("/api/status")
    assert response.status_code == 200
    data = response.get_json()
    assert data["status"] == "running"
    assert data["commit"] == "abc123"
    assert "python_version" in data
    assert "uptime" in data


# ── Extra tests for the hardening changes ──

def test_security_headers(client):
    response = client.get("/health")
    assert response.headers["X-Content-Type-Options"] == "nosniff"
    assert response.headers["X-Frame-Options"] == "DENY"


@pytest.mark.parametrize("op, expected", [
    ("add", 9), ("subtract", 5), ("divide", 3.5), ("power", 49), ("modulo", 1),
])
def test_calculator_operations(client, op, expected):
    response = client.post("/api/calculate", json={"a": 7, "b": 2, "operation": op})
    assert response.status_code == 200
    assert response.get_json()["result"] == expected


def test_calculator_modulo_by_zero(client):
    response = client.post("/api/calculate", json={"a": 7, "b": 0, "operation": "modulo"})
    assert response.status_code == 400


def test_calculator_overflow_is_400_not_500(client):
    response = client.post("/api/calculate", json={"a": 10, "b": 1000, "operation": "power"})
    assert response.status_code == 400
    assert response.get_json()["error"] == "Result is too large"


def test_calculator_complex_result_is_400(client):
    response = client.post("/api/calculate", json={"a": -8, "b": 0.5, "operation": "power"})
    assert response.status_code == 400


def test_calculator_unknown_operation(client):
    response = client.post("/api/calculate", json={"a": 1, "b": 2, "operation": "sqrt"})
    assert response.status_code == 400


def test_calculator_bad_input(client):
    assert client.post("/api/calculate", json={"a": "x", "b": 2}).status_code == 400
    assert client.post("/api/calculate", json={"a": 1}).status_code == 400
    assert client.post("/api/calculate", data="not json").status_code == 400


def test_add_numbers_bad_input(client):
    assert client.post("/api/add", json={"number1": "x", "number2": 1}).status_code == 400
    assert client.post("/api/add", data="not json").status_code == 400


def test_pipeline_run_always_passes_with_zero_fail_chance(client):
    response = client.post("/api/pipeline/run", json={"branch": "main", "fail_chance": 0})
    assert response.status_code == 200
    data = response.get_json()
    assert data["overall_status"] == "passed"
    assert all(stage["status"] == "passed" for stage in data["stages"])


def test_pipeline_run_fails_first_stage_with_fail_chance_one(client):
    data = client.post("/api/pipeline/run", json={"fail_chance": 1}).get_json()
    assert data["overall_status"] == "failed"
    assert data["stages"][0]["status"] == "failed"
    assert all(stage["status"] == "skipped" for stage in data["stages"][1:])


@pytest.mark.parametrize("value", ["abc", 2, -0.5])
def test_pipeline_run_rejects_bad_fail_chance(client, value):
    response = client.post("/api/pipeline/run", json={"fail_chance": value})
    assert response.status_code == 400


def test_unknown_route_is_json_404(client):
    response = client.get("/does-not-exist")
    assert response.status_code == 404
    assert response.get_json()["code"] == 404
