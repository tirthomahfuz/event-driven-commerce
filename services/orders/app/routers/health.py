"""Liveness endpoint.

Intentionally cheap: returns 200 if the process is up. It does NOT touch the DB
-- a transient DB blip should not make the ALB pull every task. A DB-backed
readiness probe (/ready) is deferred to a later step. See DECISIONS.md.
"""

from fastapi import APIRouter

router = APIRouter(tags=["health"])


@router.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}
