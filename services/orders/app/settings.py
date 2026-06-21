from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    database_url: str | None = None
    db_host: str = "localhost"
    db_port: int = 5432
    db_name: str = "orders"
    db_username: str = "orders_app"
    db_password: str | None = None
    log_level: str = "INFO"

    @property
    def sqlalchemy_database_url(self) -> str:
        if self.database_url:
            return self.database_url
        if not self.db_password:
            raise ValueError("Set DATABASE_URL or DB_PASSWORD before connecting to Postgres")
        return (
            f"postgresql+psycopg://{self.db_username}:{self.db_password}"
            f"@{self.db_host}:{self.db_port}/{self.db_name}"
        )


@lru_cache
def get_settings() -> Settings:
    return Settings()
