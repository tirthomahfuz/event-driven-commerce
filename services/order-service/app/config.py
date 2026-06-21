"""Application configuration.

The DB connection is resolved from one of two sources, in priority order:

1. DATABASE_URL (used by local dev via .env.local) -- taken as-is.
2. Discrete vars assembled into a URL (the AWS path): DB_HOST, DB_PORT,
   DB_NAME, DB_USERNAME, DB_PASSWORD. The RDS-managed secret rotates and exposes
   a `password` field (not a URL), so the URL is assembled in-process each start
   -- which means credential rotation "just works".

See DECISIONS.md ("DB connection config: dual-source").
"""

from __future__ import annotations

from functools import lru_cache
from urllib.parse import quote_plus

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(case_sensitive=False, extra="ignore")

    # Source 1: full URL (local dev).
    database_url: str | None = None

    # Source 2: discrete vars (AWS path).
    db_host: str | None = None
    db_port: int = 5432
    db_name: str | None = None
    db_username: str | None = None
    db_password: str | None = None

    app_port: int = 8000
    log_level: str = "INFO"

    @property
    def sqlalchemy_url(self) -> str:
        if self.database_url:
            return self._normalize_driver(self.database_url)

        missing = [
            name
            for name, value in (
                ("DB_HOST", self.db_host),
                ("DB_NAME", self.db_name),
                ("DB_USERNAME", self.db_username),
                ("DB_PASSWORD", self.db_password),
            )
            if not value
        ]
        if missing:
            raise RuntimeError(
                "Database is not configured. Set DATABASE_URL, or provide all of "
                "DB_HOST, DB_NAME, DB_USERNAME, DB_PASSWORD (DB_PORT optional). "
                f"Missing: {', '.join(missing)}."
            )

        # Password is URL-encoded so rotated special characters are safe.
        return (
            "postgresql+psycopg://"
            f"{quote_plus(self.db_username)}:{quote_plus(self.db_password)}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )

    @staticmethod
    def _normalize_driver(url: str) -> str:
        """Ensure SQLAlchemy uses the psycopg (v3) driver regardless of the
        scheme we were handed."""
        if url.startswith("postgresql+"):
            return url
        if url.startswith("postgresql://"):
            return "postgresql+psycopg://" + url[len("postgresql://") :]
        if url.startswith("postgres://"):
            return "postgresql+psycopg://" + url[len("postgres://") :]
        return url


@lru_cache
def get_settings() -> Settings:
    return Settings()
