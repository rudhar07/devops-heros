"""Test setup: every test runs against a fresh in-memory SQLite database.

The real PostgreSQL database is never touched. The app's get_db dependency is
overridden, so the routes use the test session factory instead.
"""
import os

# Must be set before the app is imported (settings are read at import time).
os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("APP_ENV", "test")

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from app.db import Base, get_db
from app.main import app


@pytest.fixture()
def session_factory():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,  # one shared connection = one in-memory DB
    )
    Base.metadata.create_all(bind=engine)
    yield sessionmaker(bind=engine, autoflush=False, autocommit=False)
    Base.metadata.drop_all(bind=engine)
    engine.dispose()


@pytest.fixture()
def client(session_factory):
    def override_get_db():
        db = session_factory()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()


@pytest.fixture()
def make_task(client):
    def _make(**overrides):
        body = {"title": "Write Helm chart", "priority": "HIGH", "assignee": "Rudhar"}
        body.update(overrides)
        response = client.post("/api/tasks", json=body)
        assert response.status_code == 201, response.text
        return response.json()

    return _make
