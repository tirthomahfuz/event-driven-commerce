import logging
from uuid import uuid4

from fastapi import Depends, FastAPI, Request, Response
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Order
from app.schemas import OrderCreate, OrderRead


logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s trace_id=%(trace_id)s %(message)s",
)
logger = logging.getLogger("orders")


class TraceIdFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        if not hasattr(record, "trace_id"):
            record.trace_id = "-"
        return True


logger.addFilter(TraceIdFilter())

app = FastAPI(title="Order Service", version="0.1.0")


@app.middleware("http")
async def add_trace_id(request: Request, call_next):
    trace_id = request.headers.get("x-request-id") or str(uuid4())
    request.state.trace_id = trace_id
    response: Response = await call_next(request)
    response.headers["x-request-id"] = trace_id
    return response


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/api/orders", response_model=OrderRead, status_code=201)
def create_order(
    payload: OrderCreate,
    request: Request,
    db: Session = Depends(get_db),
) -> Order:
    order = Order(
        customer_email=payload.customer_email,
        sku=payload.sku,
        quantity=payload.quantity,
    )
    db.add(order)
    db.commit()
    db.refresh(order)
    logger.info(
        "order.created",
        extra={"trace_id": request.state.trace_id},
    )
    return order


@app.get("/api/orders", response_model=list[OrderRead])
def list_orders(db: Session = Depends(get_db)) -> list[Order]:
    return list(db.scalars(select(Order).order_by(Order.created_at.desc()).limit(25)))
