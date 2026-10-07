import pytest

from app.web import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    with app.test_client() as client:
        yield client


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_index_lists_operations(client, monkeypatch):
    monkeypatch.setenv("GIT_SHA", "abc123")
    data = client.get("/").get_json()
    assert data["app"] == "session16-calculator"
    assert data["commit"] == "abc123"
    assert data["operations"] == ["add", "divide", "multiply", "subtract"]


@pytest.mark.parametrize(
    "operation, a, b, expected",
    [
        ("add", 10, 5, 15),
        ("subtract", 10, 5, 5),
        ("multiply", 10, 5, 50),
        ("divide", 10, 4, 2.5),
    ],
)
def test_operations(client, operation, a, b, expected):
    response = client.get(f"/api/{operation}?a={a}&b={b}")
    assert response.status_code == 200
    assert response.get_json()["result"] == expected


def test_divide_by_zero_is_400(client):
    response = client.get("/api/divide?a=1&b=0")
    assert response.status_code == 400
    assert "Cannot divide by zero" in response.get_json()["error"]


def test_missing_parameter_is_400(client):
    assert client.get("/api/add?a=1").status_code == 400


def test_non_number_is_400(client):
    assert client.get("/api/add?a=one&b=2").status_code == 400


def test_unknown_operation_is_404(client):
    assert client.get("/api/power?a=2&b=3").status_code == 404
