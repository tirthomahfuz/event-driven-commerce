"""Database engine and session management.

The engine is built from Settings.sqlalchemy_url (dual-source: DATABASE_URL or
assembled discrete vars). create_engine does not open a connection until first
use, so importing this module is cheap and side-effect-free.
"""

from __future__ import annotations

from collections.abc import Generator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.config import get_settings

_settings = get_settings()

engine = create_engine(
    _settings.sqlalchemy_url,
    pool_pre_ping=True,  # transparently recover from dropped connections
    future=True,
)

SessionLocal = sessionmaker(
    bind=engine,
    autoflush=False,
    expire_on_commit=False,
)


def get_session() -> Generator[Session, None, None]:
    """FastAPI dependency: yields a session scoped to one request."""
    with SessionLocal() as session:
        yield session
