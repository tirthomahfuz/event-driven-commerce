"""FastAPI application entrypoint.

Run locally:  uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
"""

from __future__ import annotations

from fastapi import FastAPI

from app.config import get_settings
from app.logging import configure_logging
from app.middleware import TraceContextMiddleware
from app.routers import health, orders


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging(settings.log_level)

    app = FastAPI(title="Order Service", version="0.1.0")
    app.add_middleware(TraceContextMiddleware)
    app.include_router(health.router)
    app.include_router(orders.router)
    return app


app = create_app()
