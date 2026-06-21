# Decisions Log

This file records meaningful choices for the event-driven order & inventory
pipeline. Each entry captures: what we chose, what we rejected, and why.

The log is append-only. Newest entries go at the bottom.

---

## 2026-06-21 — Project operating model: phased vertical slices

- **Chose:** Build the system in thin, end-to-end vertical slices. Phase 1 is
  only `Next.js -> FastAPI -> Postgres (RDS)`, provisioned with Terraform,
  deployed via GitHub Actions, with CloudWatch logging and Secrets Manager.
- **Rejected:** Scaffolding the full target architecture (SQS/MSK event
  backbone, multiple consumers, S3 thumbnail Lambda, full observability) up
  front.
- **Why:** The goal is to understand each piece of infrastructure as it is
  introduced. A big-bang scaffold produces a lot of code nobody can reason
  about, hides which resource does what, and makes failures hard to localize.
  One working slice gives a real reference point (a request that flows browser
  -> API -> DB) before we add asynchronous complexity.

## 2026-06-21 — Secrets handling from day one

- **Chose:** Store all credentials (DB password, app secrets) in AWS Secrets
  Manager and read them at runtime. No secrets in source, `.tf` files, or
  committed env files.
- **Rejected:** Plain environment variables baked into task definitions, or a
  committed `.env` for "just the dev DB."
- **Why:** Secrets in Terraform end up in plaintext state. Secrets in task
  definitions show up in the ECS console and CloudFormation/Terraform diffs.
  Starting clean avoids a painful retrofit later and models real-world hygiene.

## 2026-06-21 — Order idempotency: minimal column now vs. full table later

- **Chose:** A nullable, `UNIQUE` `idempotency_key` column on `orders`, checked
  on the create-order path: if a key is supplied and already exists, return the
  existing order instead of creating a duplicate. Nothing more.
- **Rejected (for now):** A dedicated `idempotency_keys` table that stores the
  key, a request fingerprint, the response payload, and a TTL — plus any async
  retry/replay machinery.
- **Why:** Duplicate orders from a client retry or double-submit are a real
  Phase 1 correctness bug, not a future concern, so we fix it now. But the full
  table (request hashing, cached responses, expiry) is weight we don't need until
  the async phases, where retries and at-least-once delivery make it genuinely
  necessary. The column gives correct dedupe today; we upgrade to the table when
  eventing arrives, and we'll log that upgrade when it happens.

## 2026-06-21 — Phase 1 schema confirmed (products, orders, order_items)

- **Chose:** Three tables. Money as integer `*_cents` + `currency`. UUID primary
  keys (`gen_random_uuid()`). `status` as `text` + `CHECK`. Line items snapshot
  `unit_price_cents`. `orders` carries `trace_id` (nullable) and the
  `idempotency_key` above. No `customers`/`users` table in Phase 1.
- **Rejected:** `NUMERIC` money, `bigserial` PKs, native PG enum for status, a
  separate identity table — each deferred with reasons captured in Step 1.
- **Why:** Smallest schema that truthfully represents "a customer placed an
  order of priced line items," while staying event-friendly (UUIDs) and
  migration-friendly (text status) for later phases.

## 2026-06-21 — Env var contract: DATABASE_URL

- **Chose:** The order service reads its Postgres connection from a single env
  var, `DATABASE_URL` (standard `postgresql://…` URL). This name/shape is the
  contract shared with the infra agent; locally it comes from `.env.local`, in
  AWS it comes from Secrets Manager.
- **Rejected:** Separate `DB_HOST`/`DB_PORT`/`DB_USER`/`DB_PASSWORD` vars.
- **Why:** One URL is the simplest stable contract across local/CI/AWS and lets
  the secret source change without any app code change. Driver selection (e.g.
  psycopg) is handled inside the app, not in the contract.
