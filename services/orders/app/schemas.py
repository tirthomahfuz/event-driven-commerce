from datetime import datetime

from pydantic import BaseModel, EmailStr, Field


class OrderCreate(BaseModel):
    customer_email: EmailStr
    sku: str = Field(min_length=1, max_length=64)
    quantity: int = Field(gt=0, le=100)


class OrderRead(BaseModel):
    id: str
    customer_email: EmailStr
    sku: str
    quantity: int
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}
