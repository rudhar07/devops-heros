"""Application settings, read from environment variables.

Kubernetes passes the non-secret parts (DB_HOST, DB_PORT, DB_NAME, APP_ENV,
LOG_LEVEL) from a ConfigMap and the credentials (DB_USER, DB_PASSWORD) from a
Secret. Docker Compose and local runs may set a full DATABASE_URL instead.
"""
from sqlalchemy.engine import URL
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_name: str = "TaskBoard API"
    app_version: str = "2.0.0"
    app_env: str = "local"
    log_level: str = "INFO"
    git_sha: str = "local"

    # Full URL wins if set (Compose / local), otherwise the parts are used.
    database_url: str | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "taskboard"
    db_user: str = "taskboard"
    db_password: str = ""

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self.database_url
        # URL.create escapes special characters in the password for us.
        return URL.create(
            "postgresql+psycopg",
            username=self.db_user,
            password=self.db_password,
            host=self.db_host,
            port=self.db_port,
            database=self.db_name,
        ).render_as_string(hide_password=False)


settings = Settings()
