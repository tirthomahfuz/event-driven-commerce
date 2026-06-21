"use client";

import { FormEvent, useState } from "react";

type Order = {
  id: string;
  customer_email: string;
  sku: string;
  quantity: number;
  status: string;
  created_at: string;
};

export default function Home() {
  const [email, setEmail] = useState("learner@example.com");
  const [sku, setSku] = useState("SKU-001");
  const [quantity, setQuantity] = useState(1);
  const [lastOrder, setLastOrder] = useState<Order | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function submitOrder(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError(null);
    setIsSubmitting(true);

    const traceId = crypto.randomUUID();
    const response = await fetch("/api/orders", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-request-id": traceId,
      },
      body: JSON.stringify({
        customer_email: email,
        sku,
        quantity,
      }),
    });

    setIsSubmitting(false);

    if (!response.ok) {
      setError(`Order request failed with ${response.status}`);
      return;
    }

    setLastOrder(await response.json());
  }

  return (
    <main className="shell">
      <section className="hero">
        <p className="eyebrow">Phase 1a</p>
        <h1>Place an order through the first vertical slice.</h1>
        <p>
          This page sends a request to the FastAPI order service and stores the
          order in Postgres. Events and consumers come later.
        </p>
      </section>

      <form className="card" onSubmit={submitOrder}>
        <label>
          Customer email
          <input value={email} onChange={(event) => setEmail(event.target.value)} />
        </label>
        <label>
          SKU
          <input value={sku} onChange={(event) => setSku(event.target.value)} />
        </label>
        <label>
          Quantity
          <input
            min="1"
            type="number"
            value={quantity}
            onChange={(event) => setQuantity(Number(event.target.value))}
          />
        </label>
        <button disabled={isSubmitting} type="submit">
          {isSubmitting ? "Placing order..." : "Place order"}
        </button>
      </form>

      {error && <p className="error">{error}</p>}
      {lastOrder && (
        <section className="card">
          <h2>Last order</h2>
          <pre>{JSON.stringify(lastOrder, null, 2)}</pre>
        </section>
      )}
    </main>
  );
}
