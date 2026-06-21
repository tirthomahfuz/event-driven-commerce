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

## 2026-06-21 — DB connection config: dual-source (supersedes "DATABASE_URL only")

- **Chose:** The config layer accepts two sources, in priority order:
  1. If `DATABASE_URL` is set (local dev via `.env.local`), use it directly.
  2. Otherwise assemble the connection URL from `DB_HOST`, `DB_PORT`, `DB_NAME`,
     `DB_USERNAME`, `DB_PASSWORD` (the AWS path).
  `.env.local` continues to use `DATABASE_URL` for local simplicity.
- **Rejected:** The earlier "`DATABASE_URL` only, discrete vars rejected"
  decision — now overridden.
- **Why:** The RDS-managed secret in Secrets Manager **rotates** and exposes a
  JSON object with a `password` field, not a ready-made connection URL. The ECS
  task definition therefore injects `DB_HOST`/`DB_PORT`/`DB_NAME`/`DB_USERNAME`
  as plain env and sources `DB_PASSWORD` separately from the rotating secret, so
  AWS literally cannot hand us a single `DATABASE_URL`. Supporting both keeps
  local dev one-line simple while matching how AWS delivers rotating creds.
  Assembling the URL in-process also means rotation "just works": each task/
  process start reads the current password and builds a fresh URL. The password
  is URL-encoded during assembly so special characters from rotation are safe.

## 2026-06-21 — Service runtime contract (port 8000, /health, migrations-in-image)

- **Chose:** The service listens on **port 8000**; exposes **`GET /health`**
  returning 200 as the ALB target health check; and the **same container image**
  can run `alembic upgrade head` via command override (CI runs migrations as a
  one-off ECS task using this image), so Alembic is invokable from the container,
  not only locally.
- **Rejected:** A separate dedicated migration image; running migrations only on
  developer laptops; an arbitrary/!=8000 app port.
- **Why:** The ALB needs a fixed port and a cheap liveness endpoint to decide
  routing. One image for both API and migrations guarantees migration code
  matches running code (no drift) and is the standard ECS "run-task migrations,
  then start service" pattern. `/health` is intentionally a cheap liveness check
  (process up), not a DB readiness probe — see Step 3 design note for the
  tradeoff.
