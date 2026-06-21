"""Order business logic, independent of HTTP.

Correctness rules enforced here:
- Idempotency: if an Idempotency-Key was supplied and already exists, return the
  existing order instead of creating a duplicate.
- Validate that EVERY product_id exists before inserting anything.
- Compute total_cents server-side as sum(unit_price_cents * quantity), snapshotting
  each product's current price onto the line item.
- The whole insert is one transaction: an unknown product writes no partial row.
"""

from __future__ import annotations

import logging
import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.models import Order, OrderItem, Product
from app.schemas import OrderCreate

logger = logging.getLogger("app.services.orders")


class ProductNotFoundError(Exception):
    """Raised when one or more product_ids in a create request do not exist."""

    def __init__(self, product_ids: list[uuid.UUID]) -> None:
        self.product_ids = product_ids
        joined = ", ".join(str(pid) for pid in product_ids)
        super().__init__(f"Unknown product_id(s): {joined}")


def get_order(session: Session, order_id: uuid.UUID) -> Order | None:
    return session.get(Order, order_id)


def create_order(
    session: Session,
    payload: OrderCreate,
    *,
    idempotency_key: str | None,
    trace_id: str | None,
) -> tuple[Order, bool]:
    """Create an order (or return an existing one for a known idempotency key).

    Returns (order, created): created=False means an idempotent replay.
    """
    if idempotency_key:
        existing = session.scalar(
            select(Order).where(Order.idempotency_key == idempotency_key)
        )
        if existing is not None:
            logger.info(
                "idempotent replay",
                extra={"order_id": str(existing.id), "idempotency_key": idempotency_key},
            )
            return existing, False

    requested_ids = [item.product_id for item in payload.items]

    # Validate ALL products exist before we build/insert anything.
    products = session.scalars(
        select(Product).where(Product.id.in_(requested_ids))
    ).all()
    products_by_id = {product.id: product for product in products}

    missing = [pid for pid in requested_ids if pid not in products_by_id]
    if missing:
        # Nothing has been added to the session yet, so no partial row exists.
        raise ProductNotFoundError(missing)

    order = Order(
        customer_email=str(payload.customer_email),
        status="placed",
        idempotency_key=idempotency_key,
        trace_id=trace_id,
        total_cents=0,
        currency="USD",
    )

    total_cents = 0
    currency = "USD"
    for item in payload.items:
        product = products_by_id[item.product_id]
        currency = product.currency  # Phase 1 assumes a single currency
        order.items.append(
            OrderItem(
                product=product,
                product_id=product.id,
                quantity=item.quantity,
                unit_price_cents=product.price_cents,
            )
        )
        total_cents += product.price_cents * item.quantity

    order.total_cents = total_cents
    order.currency = currency

    session.add(order)
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        # Most likely a concurrent create with the same idempotency key won the
        # race; return the now-existing order instead of erroring.
        if idempotency_key:
            existing = session.scalar(
                select(Order).where(Order.idempotency_key == idempotency_key)
            )
            if existing is not None:
                logger.info(
                    "idempotent replay (race)",
                    extra={"order_id": str(existing.id), "idempotency_key": idempotency_key},
                )
                return existing, False
        raise

    session.refresh(order)
    logger.info(
        "order created",
        extra={
            "order_id": str(order.id),
            "total_cents": order.total_cents,
            "item_count": len(order.items),
        },
    )
    return order, True
