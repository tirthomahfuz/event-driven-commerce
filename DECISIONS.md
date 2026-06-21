# Decisions

## 2026-06-21 - Phase 1 scope

- Chose: Start with a thin vertical slice: Next.js -> FastAPI -> Postgres on RDS, provisioned with Terraform, deployed via GitHub Actions, with CloudWatch logging and Secrets Manager.
- Rejected: Scaffolding the full end-state architecture up front, including queues, consumers, image-processing Lambda, analytics, Kafka/MSK-ready abstractions, and EKS-ready abstractions.
- Why: The first goal is to understand one production-shaped path end to end before adding event-driven complexity. This keeps the infrastructure explainable and makes each later phase a deliberate extension instead of unused scaffolding.

## 2026-06-21 - Split Phase 1 into public-first and private-networking steps

- Chose: Phase 1a runs the ECS tasks in public subnets with public IPs, protected by security groups, with no NAT gateway and no VPC endpoints. Phase 1b moves ECS and RDS into private subnets and adds the VPC endpoints needed for image pulls, logs, and secret reads.
- Rejected: Starting immediately with private subnets, NAT, and VPC endpoints.
- Why: Public-subnet Fargate is not the final posture, but it makes the first request path easier to see: ALB -> ECS -> RDS, with fewer moving parts. The alternative is more production-like on day one, but failures become harder to explain because image pulls, log delivery, Secrets Manager access, route tables, endpoint security groups, and database access can all break at once.

## 2026-06-21 - Prefer VPC endpoints over NAT gateway for Phase 1b service access

- Chose: In Phase 1b, private ECS tasks should use VPC endpoints for the AWS services they need: ECR API, ECR Docker, S3 gateway for ECR image layers, CloudWatch Logs, and Secrets Manager.
- Rejected: A NAT gateway as the default way for private ECS tasks to reach AWS services.
- Why: NAT is simpler to understand at first because private tasks get general outbound internet access through one managed gateway, but it is broad and relatively expensive for a learning project. A NAT gateway is roughly 45 USD/month per AZ before data processing in many US regions, so two AZs is roughly 90 USD/month plus per-GB charges. Interface VPC endpoints are usually roughly 7 USD/month each per AZ plus data processing, and we need several of them; for five endpoints across two AZs that can land around 70 USD/month plus data. The endpoint path is not always cheaper, but it teaches the important production tradeoff: narrower AWS-service-only egress and clearer dependency mapping instead of broad internet egress. If the app later needs arbitrary outbound internet calls, NAT may become the better choice or we may combine both.

## 2026-06-21 - Run Alembic migrations as one-off ECS tasks

- Chose: GitHub Actions builds and pushes the FastAPI image, registers a new ECS task definition revision, runs `alembic upgrade head` as a one-off Fargate task using that new image, waits for it to succeed, and only then updates the long-running API service.
- Rejected: Running migrations directly from the GitHub-hosted runner.
- Why: The runner should not need database network access or plaintext database credentials. Running migrations inside ECS uses the same container image, task role, security group, subnet placement, and Secrets Manager injection model as the service itself. The tradeoff is that deploys depend on ECS task startup and migration discipline; backward-incompatible migrations still need careful sequencing.

## 2026-06-21 - Let CI/CD own ECS desired count after initial Terraform apply

- Chose: Terraform creates ECS services at desired count zero, and the deploy workflow updates them to one task after real images have been pushed.
- Rejected: Having Terraform create services with desired count one before any application image exists.
- Why: ECS can register a task definition that references an image tag before the image exists, but a service with desired count one would immediately try and fail to pull it. Starting at zero lets Terraform create the infrastructure first, then CI/CD supplies the application artifact and starts the services. Terraform ignores later desired-count drift so routine deploys do not fight the pipeline.

## 2026-06-21 - Keep application code out of the infra branch

- Chose: This branch owns infrastructure, pipeline scaffolding, and runtime contracts only.
- Rejected: Defining the FastAPI app, Next.js app, Alembic migrations, or database schema in the infra branch.
- Why: A parallel app branch owns the application layer and has an approved schema with `products`, `orders`, and `order_items`. Keeping app code out of the infra branch avoids schema conflicts and makes the boundary clear: infrastructure supplies runtime environment and deployment mechanics; the app supplies images and migrations that conform to the contract.

## 2026-06-21 - Revert pre-release Next.js baseline

- Chose: The app branch should use the latest stable Next.js baseline, not a canary/pre-release framework, and should either accept and document the current moderate PostCSS advisory or pin a compatible patched PostCSS version with an overrides entry.
- Rejected: Shipping a Next.js canary as the default baseline just to clear `npm audit`.
- Why: A pre-release framework can introduce unrelated instability into a learning project. The real tradeoff is between a known moderate advisory in the stable dependency tree and the operational uncertainty of a canary. Stable Next.js is the better default; if the PostCSS override is compatible, that is the cleaner mitigation.
