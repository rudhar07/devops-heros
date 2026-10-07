from pathlib import Path

from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from app.config import Settings

BACKEND_DIR = Path(__file__).resolve().parents[1]


def test_database_url_built_from_parts_escapes_password():
    s = Settings(database_url=None, db_host="pg.example", db_port=5433, db_name="tb",
                 db_user="tb", db_password="p@ss/word")
    assert s.sqlalchemy_url == "postgresql+psycopg://tb:p%40ss%2Fword@pg.example:5433/tb"


def test_full_database_url_wins():
    s = Settings(database_url="sqlite:///x.db", db_host="ignored")
    assert s.sqlalchemy_url == "sqlite:///x.db"


def test_alembic_migrations_upgrade_and_downgrade(tmp_path):
    db_url = f"sqlite:///{tmp_path / 'migrate.db'}"
    cfg = Config(str(BACKEND_DIR / "alembic.ini"))
    cfg.set_main_option("script_location", str(BACKEND_DIR / "alembic"))
    cfg.attributes["db_url"] = db_url
    cfg.attributes["configure_logger"] = False

    command.upgrade(cfg, "head")
    engine = create_engine(db_url)
    columns = {c["name"] for c in inspect(engine).get_columns("tasks")}
    assert {"id", "title", "status", "priority", "due_date", "updated_at"} <= columns
    indexes = {i["name"] for i in inspect(engine).get_indexes("tasks")}
    assert {"ix_tasks_status", "ix_tasks_priority"} <= indexes

    command.downgrade(cfg, "base")
    assert "tasks" not in inspect(engine).get_table_names()
    engine.dispose()
