# Decisions

## 2026-06-21 - Phase 1 scope

- Chose: Start with a thin vertical slice: Next.js -> FastAPI -> Postgres on RDS, provisioned with Terraform, deployed via GitHub Actions, with CloudWatch logging and Secrets Manager.
- Rejected: Scaffolding the full end-state architecture up front, including queues, consumers, image-processing Lambda, analytics, Kafka/MSK-ready abstractions, and EKS-ready abstractions.
- Why: The first goal is to understand one production-shaped path end to end before adding event-driven complexity. This keeps the infrastructure explainable and makes each later phase a deliberate extension instead of unused scaffolding.
