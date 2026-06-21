"""Alembic environment.

Wires Alembic to the application so migrations use the exact same dual-source DB
resolution as the running app, and so --autogenerate / `alembic check` diff
against the ORM models (the source of truth).
"""

from __future__ import annotations

from logging.config import fileConfig

from alembic import context
from sqlalchemy import engine_from_config, pool

from app.config import get_settings
from app.models import Base

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

# Inject the runtime URL from app settings (dual-source). Escape % because
# ConfigParser treats it as interpolation syntax (a URL-encoded password can
# contain %XX sequences).
_db_url = get_settings().sqlalchemy_url
config.set_main_option("sqlalchemy.url", _db_url.replace("%", "%%"))

target_metadata = Base.metadata

# Compare column types but NOT server defaults: Postgres normalizes defaults
# (e.g. 'USD' -> 'USD'::character varying), which would otherwise produce false
# "drift" in `alembic check`. Server defaults are still created by the migration.
_COMPARE_OPTS = {"compare_type": True, "compare_server_default": False}


def run_migrations_offline() -> None:
    context.configure(
        url=config.get_main_option("sqlalchemy.url"),
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        **_COMPARE_OPTS,
    )
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    connectable = engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            **_COMPARE_OPTS,
        )
        with context.begin_transaction():
            context.run_migrations()


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
