"""Trace-context middleware.

Reads the inbound X-Request-Id (generating one when absent), binds it to the
logging ContextVar and request.state, echoes it back on the response, and emits
one structured "request completed" log line per request.

Graduates to W3C `traceparent` in Phase 5.
"""

from __future__ import annotations

import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.types import ASGIApp

from app.logging import trace_id_var

TRACE_HEADER = "X-Request-Id"

logger = logging.getLogger("app.middleware")


class TraceContextMiddleware(BaseHTTPMiddleware):
    def __init__(self, app: ASGIApp) -> None:
        super().__init__(app)

    async def dispatch(self, request: Request, call_next):
        trace_id = request.headers.get(TRACE_HEADER) or str(uuid.uuid4())
        token = trace_id_var.set(trace_id)
        request.state.trace_id = trace_id
        start = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            duration_ms = round((time.perf_counter() - start) * 1000, 2)
            logger.exception(
                "request failed",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "duration_ms": duration_ms,
                },
            )
            # Reset only after logging so the failure line still carries trace_id.
            trace_id_var.reset(token)
            raise

        duration_ms = round((time.perf_counter() - start) * 1000, 2)
        response.headers[TRACE_HEADER] = trace_id
        logger.info(
            "request completed",
            extra={
                "method": request.method,
                "path": request.url.path,
                "status_code": response.status_code,
                "duration_ms": duration_ms,
            },
        )
        trace_id_var.reset(token)
        return response
