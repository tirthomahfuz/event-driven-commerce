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
