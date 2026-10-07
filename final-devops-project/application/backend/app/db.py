from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from .config import settings

_url = settings.sqlalchemy_url
# pool_pre_ping drops dead connections after a PostgreSQL restart.
# connect_timeout keeps /ready fast when the database host is wrong.
_engine_options = (
    {"pool_size": 5, "max_overflow": 5, "connect_args": {"connect_timeout": 3}}
    if _url.startswith("postgresql")
    else {}
)
engine = create_engine(_url, pool_pre_ping=True, **_engine_options)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


def get_db() -> Iterator[Session]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
