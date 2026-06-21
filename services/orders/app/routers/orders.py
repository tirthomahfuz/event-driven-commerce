"""HTTP layer for orders: parse/validate, delegate to the service, serialize."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, Request, Response, status
from sqlalchemy.orm import Session

from app.db import get_session
from app.schemas import OrderCreate, OrderOut, serialize_order
from app.services import orders as orders_service
from app.services.orders import ProductNotFoundError

router = APIRouter(prefix="/orders", tags=["orders"])


@router.post("", response_model=OrderOut, status_code=status.HTTP_201_CREATED)
def create_order(
    payload: OrderCreate,
    request: Request,
    response: Response,
    session: Session = Depends(get_session),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> OrderOut:
    trace_id = getattr(request.state, "trace_id", None)
    try:
        order, created = orders_service.create_order(
            session,
            payload,
            idempotency_key=idempotency_key,
            trace_id=trace_id,
        )
    except ProductNotFoundError as exc:
        raise HTTPException(status_code=status.HTTP_422_UNPROCESSABLE_ENTITY, detail=str(exc))

    # Idempotent replay of an existing order is a 200, not a fresh 201.
    if not created:
        response.status_code = status.HTTP_200_OK

    return serialize_order(order)


@router.get("/{order_id}", response_model=OrderOut)
def get_order(
    order_id: uuid.UUID,
    session: Session = Depends(get_session),
) -> OrderOut:
    order = orders_service.get_order(session, order_id)
    if order is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Order not found")
    return serialize_order(order)
