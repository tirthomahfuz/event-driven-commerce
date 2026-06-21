"""Pydantic request/response models and the ORM->response serializer.

Clients send only product_id + quantity; unit prices and totals are computed
server-side and never trusted from the client.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.models import Order


class OrderItemIn(BaseModel):
    product_id: uuid.UUID
    quantity: int = Field(gt=0)


class OrderCreate(BaseModel):
    customer_email: EmailStr
    items: list[OrderItemIn] = Field(min_length=1)


class OrderItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    product_id: uuid.UUID
    name: str
    quantity: int
    unit_price_cents: int


class OrderOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    status: str
    customer_email: str
    currency: str
    total_cents: int
    idempotency_key: str | None
    trace_id: str | None
    items: list[OrderItemOut]
    created_at: datetime
    updated_at: datetime


def serialize_order(order: Order) -> OrderOut:
    return OrderOut(
        id=order.id,
        status=order.status,
        customer_email=order.customer_email,
        currency=order.currency,
        total_cents=order.total_cents,
        idempotency_key=order.idempotency_key,
        trace_id=order.trace_id,
        created_at=order.created_at,
        updated_at=order.updated_at,
        items=[
            OrderItemOut(
                product_id=item.product_id,
                name=item.product.name,
                quantity=item.quantity,
                unit_price_cents=item.unit_price_cents,
            )
            for item in order.items
        ],
    )
