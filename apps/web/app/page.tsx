"use client";

import { FormEvent, useMemo, useState } from "react";

import {
  CreateOrderResult,
  FetchOrderResult,
  Order,
  OrderNotFoundError,
  createOrder,
  fetchOrder,
} from "../lib/orders";

type DraftItem = {
  key: string;
  product_id: string;
  quantity: number;
};

type ResultState =
  | {
      type: "created";
      value: CreateOrderResult;
    }
  | {
      type: "fetched";
      value: FetchOrderResult;
    };

function createDraftItem(): DraftItem {
  return {
    key: crypto.randomUUID(),
    product_id: "",
    quantity: 1,
  };
}

function formatMoney(cents: number, currency: string) {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency,
  }).format(cents / 100);
}

function OrderSummary({ order, requestId }: { order: Order; requestId: string }) {
  return (
    <section className="card result-card">
      <div className="result-heading">
        <div>
          <p className="eyebrow">Order result</p>
          <h2>{order.id}</h2>
        </div>
        <span className="status-pill">{order.status}</span>
      </div>

      <dl className="details">
        <div>
          <dt>Total</dt>
          <dd>{formatMoney(order.total_cents, order.currency)}</dd>
        </div>
        <div>
          <dt>Created</dt>
          <dd>{new Date(order.created_at).toLocaleString()}</dd>
        </div>
        <div>
          <dt>X-Request-Id sent</dt>
          <dd className="mono">{requestId}</dd>
        </div>
      </dl>

      <div className="line-items">
        <h3>Line items</h3>
        {order.items.map((item, index) => (
          <div className="line-item-result" key={`${item.name}-${index}`}>
            <div>
              <strong>{item.name}</strong>
            </div>
            <div className="line-item-price">
              <strong>{formatMoney(item.unit_price_cents, order.currency)} each</strong>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
}

export default function Home() {
  const [customerEmail, setCustomerEmail] = useState("");
  const [items, setItems] = useState<DraftItem[]>([createDraftItem()]);
  const [lookupOrderId, setLookupOrderId] = useState("");
  const [result, setResult] = useState<ResultState | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [isFetching, setIsFetching] = useState(false);

  const canSubmit = useMemo(
    () =>
      customerEmail.trim().length > 0 &&
      items.length > 0 &&
      items.every((item) => item.product_id.trim().length > 0 && item.quantity > 0),
    [customerEmail, items],
  );

  function updateItem(key: string, updates: Partial<Omit<DraftItem, "key">>) {
    setItems((current) =>
      current.map((item) => (item.key === key ? { ...item, ...updates } : item)),
    );
  }

  function removeItem(key: string) {
    setItems((current) => current.filter((item) => item.key !== key));
  }

  async function submitOrder(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);

    try {
      const value = await createOrder({
        customer_email: customerEmail.trim(),
        items: items.map((item) => ({
          product_id: item.product_id.trim(),
          quantity: item.quantity,
        })),
      });
      setResult({ type: "created", value });
      setLookupOrderId(value.order.id);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Order request failed.");
    } finally {
      setIsSubmitting(false);
    }
  }

  async function fetchExistingOrder(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsFetching(true);

    try {
      const value = await fetchOrder(lookupOrderId.trim());
      setResult({ type: "fetched", value });
    } catch (caught) {
      if (caught instanceof OrderNotFoundError) {
        setError(caught.message);
      } else {
        setError(caught instanceof Error ? caught.message : "Fetch order request failed.");
      }
    } finally {
      setIsFetching(false);
    }
  }

  const displayedOrder = result?.value.order;
  const displayedRequestId = result?.value.requestId;

  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Phase 1a</p>
        <h1>Create and inspect orders.</h1>
        <p>
          This UI sends only customer email, product IDs, and quantities. Pricing
          and totals come back from the order service response.
        </p>
      </section>

      <section className="grid">
        <form className="card" onSubmit={submitOrder}>
          <div className="section-heading">
            <h2>Create order</h2>
            <p>Each submit generates a fresh idempotency key and trace seed.</p>
          </div>

          <label>
            Customer email
            <input
              autoComplete="email"
              inputMode="email"
              onChange={(event) => setCustomerEmail(event.target.value)}
              placeholder="customer@example.com"
              type="email"
              value={customerEmail}
            />
          </label>

          <div className="line-items">
            <div className="line-items-heading">
              <h3>Items</h3>
              <button
                className="secondary-button"
                onClick={() => setItems((current) => [...current, createDraftItem()])}
                type="button"
              >
                Add item
              </button>
            </div>

            {items.map((item, index) => (
              <div className="line-item" key={item.key}>
                <label>
                  Product ID
                  <input
                    onChange={(event) => updateItem(item.key, { product_id: event.target.value })}
                    placeholder="uuid-string"
                    value={item.product_id}
                  />
                </label>
                <label>
                  Quantity
                  <input
                    min="1"
                    onChange={(event) =>
                      updateItem(item.key, { quantity: Number(event.target.value) })
                    }
                    type="number"
                    value={item.quantity}
                  />
                </label>
                <button
                  className="danger-button"
                  disabled={items.length === 1}
                  onClick={() => removeItem(item.key)}
                  type="button"
                >
                  Remove item {index + 1}
                </button>
              </div>
            ))}
          </div>

          <button disabled={!canSubmit || isSubmitting} type="submit">
            {isSubmitting ? "Submitting..." : "Create order"}
          </button>
        </form>

        <form className="card" onSubmit={fetchExistingOrder}>
          <div className="section-heading">
            <h2>Fetch by ID</h2>
            <p>Calls GET /api/orders/&lbrace;id&rbrace; and shows 404s clearly.</p>
          </div>

          <label>
            Order ID
            <input
              onChange={(event) => setLookupOrderId(event.target.value)}
              placeholder="order uuid"
              value={lookupOrderId}
            />
          </label>

          <button disabled={lookupOrderId.trim().length === 0 || isFetching} type="submit">
            {isFetching ? "Fetching..." : "Fetch order"}
          </button>
        </form>
      </section>

      {error && <p className="error">{error}</p>}

      {displayedOrder && displayedRequestId && (
        <OrderSummary order={displayedOrder} requestId={displayedRequestId} />
      )}

      {result?.type === "created" && (
        <p className="meta-note">
          Idempotency-Key sent: <span className="mono">{result.value.idempotencyKey}</span>.
          Response status: <span className="mono">{result.value.statusCode}</span>.
        </p>
      )}
    </main>
  );
}
