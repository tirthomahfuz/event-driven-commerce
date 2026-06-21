export type OrderLineItemInput = {
  product_id: string;
  quantity: number;
};

export type CreateOrderRequest = {
  customer_email: string;
  items: OrderLineItemInput[];
};

export type OrderItem = {
  name: string;
  unit_price_cents: number;
};

export type Order = {
  id: string;
  status: string;
  total_cents: number;
  currency: string;
  items: OrderItem[];
  created_at: string;
};

export type CreateOrderResult = {
  order: Order;
  requestId: string;
  idempotencyKey: string;
  statusCode: 200 | 201;
};

export type FetchOrderResult = {
  order: Order;
  requestId: string;
};

export class OrderNotFoundError extends Error {
  constructor(orderId: string) {
    super(`Order ${orderId} was not found.`);
    this.name = "OrderNotFoundError";
  }
}

async function parseOrderResponse(response: Response): Promise<Order> {
  return response.json() as Promise<Order>;
}

export async function createOrder(payload: CreateOrderRequest): Promise<CreateOrderResult> {
  const requestId = crypto.randomUUID();
  const idempotencyKey = crypto.randomUUID();
  const response = await fetch("/api/orders", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "Idempotency-Key": idempotencyKey,
      "X-Request-Id": requestId,
    },
    body: JSON.stringify(payload),
  });

  if (response.status !== 200 && response.status !== 201) {
    throw new Error(`Order request failed with HTTP ${response.status}.`);
  }

  return {
    order: await parseOrderResponse(response),
    requestId,
    idempotencyKey,
    statusCode: response.status,
  };
}

export async function fetchOrder(orderId: string): Promise<FetchOrderResult> {
  const requestId = crypto.randomUUID();
  const response = await fetch(`/api/orders/${encodeURIComponent(orderId)}`, {
    headers: {
      "X-Request-Id": requestId,
    },
  });

  if (response.status === 404) {
    throw new OrderNotFoundError(orderId);
  }

  if (!response.ok) {
    throw new Error(`Fetch order request failed with HTTP ${response.status}.`);
  }

  return {
    order: await parseOrderResponse(response),
    requestId,
  };
}
