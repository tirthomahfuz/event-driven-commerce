# Event Driven Commerce

Learning project for an event-driven order and inventory pipeline on AWS.

The end state is intentionally broader than the current code: Next.js,
FastAPI, Postgres/RDS, ECS Fargate, Terraform, CI/CD, an event backbone,
independent consumers, image processing, and observability. We are building it
in thin vertical slices.

## Current slice: Phase 1a

Phase 1a proves the first request path:

```text
Browser -> ALB -> Next.js -> /api/orders -> ALB -> FastAPI -> RDS Postgres
```

What is deliberately **not** in Phase 1a:

- No SQS or event backbone.
- No inventory, notification, or analytics consumers.
- No image upload Lambda.
- No private ECS subnets, NAT gateway, or VPC endpoints.
- No HTTPS/domain setup yet.

Phase 1b will move ECS and RDS into private subnets and add the VPC endpoints
needed for ECR pulls, CloudWatch Logs, and Secrets Manager.

## Application ownership and deployment contract

This branch owns infrastructure and pipeline scaffolding only. The application
branch owns the Next.js app, FastAPI app, database models, and Alembic
migrations.

The app layer must conform to this Phase 1a contract:

| Contract | Required behavior |
| --- | --- |
| Canonical web path | The web application lives at `apps/web`. |
| Canonical orders path | The orders service lives at `services/orders`. |
| Web container port | The web container listens on port `3000`. |
| Orders container port | The orders container listens on port `8000`. |
| Orders health check | `GET /health` on the orders container returns HTTP `200`. |
| Migration command | The orders image can run `alembic upgrade head` as an ECS command override. |
| AWS DB env vars | AWS injects `DB_HOST`, `DB_PORT`, `DB_NAME`, and `DB_USERNAME` as plain environment variables. |
| AWS DB password | AWS injects `DB_PASSWORD` from the RDS managed Secrets Manager secret. |
| AWS database URL | AWS does **not** inject `DATABASE_URL`; the orders app must build its connection string from the DB env vars above. |
| Image build contexts | The deploy workflow builds images from `apps/web` and `services/orders`. |

The approved app schema is owned by the app branch and is expected to include
`products`, `orders`, and `order_items`. Infrastructure must not define or
override those tables.

Local development may use `DATABASE_URL` in the app branch's local environment
files for convenience. That variable is local-only; AWS uses the discrete
`DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USERNAME`, and `DB_PASSWORD` contract above.

## Phase 1a AWS resources

Before applying Terraform, understand each resource:

| Resource | What it is | Why it is needed here | What breaks if removed |
| --- | --- | --- | --- |
| S3 state bucket | Remote storage for Terraform state | Lets local work and CI share one infrastructure record | Terraform state stays local and can drift between machines |
| DynamoDB lock table | Terraform state lock | Prevents concurrent state writes | Two Terraform runs can race and corrupt state |
| VPC | Isolated AWS network | Gives ALB, ECS, and RDS a controlled network boundary | Resources have no shared network |
| Public subnets | Subnets with a route to the internet gateway | Phase 1a uses public-IP ECS tasks instead of NAT/endpoints | ALB cannot be internet-facing and ECS cannot reach AWS APIs |
| Internet gateway | VPC attachment for internet routing | Allows public subnet resources to send/receive internet traffic | Public subnets are not actually public |
| Route table | Route from public subnets to the internet gateway | Makes the public subnet path explicit | ECS cannot pull images/read secrets/write logs without NAT/endpoints |
| Security groups | Stateful firewalls | ALB, ECS, and RDS only accept expected traffic | Services are either unreachable or too exposed |
| ECR repositories | Container image stores | GitHub Actions needs somewhere to push images | ECS has no deployable image source |
| ECS cluster | Fargate service grouping | Hosts the web and order services | No compute control plane for the containers |
| ECS task definitions | Container runtime specs | Define image, CPU, memory, ports, env, secrets, logs | ECS does not know how to run each container |
| ECS services | Long-running task managers | Keep web/API tasks running after deploy | Containers only run manually and do not self-heal |
| Application Load Balancer | Public HTTP entry point | Routes `/` to Next.js and `/api/*` to FastAPI | Browser traffic cannot reliably reach the services |
| Target groups/listener rules | ALB routing destinations | Connect ALB paths to ECS task IPs | ALB receives traffic but has nowhere correct to send it |
| RDS Postgres | Managed relational database | Persists orders beyond container restarts | Orders disappear or require a self-managed database |
| RDS managed master secret | AWS-managed DB credential in Secrets Manager | Avoids plaintext DB passwords in Terraform state | DB password would need to be supplied and stored unsafely |
| CloudWatch log groups | Central container log storage | Lets us debug deploys and request handling | Container logs disappear with tasks |
| CloudWatch alarms | Basic health/error signals | Teaches unhealthy-target and ALB 5xx detection | Failures are only noticed manually |
| GitHub OIDC provider | Trust link from GitHub Actions to AWS | Avoids static AWS access keys in GitHub | CI/CD needs long-lived AWS credentials |
| GitHub deploy role | Least-privilege role for deploy workflow | Allows image pushes, task registration, migration task, service update | GitHub Actions cannot deploy |

## Terraform flow

Bootstrap remote state once:

```bash
cd infra/bootstrap
terraform init
terraform plan -var "state_bucket_name=<globally-unique-bucket-name>"
terraform apply -var "state_bucket_name=<globally-unique-bucket-name>"
```

Then configure Phase 1a backend:

```bash
cd ../phase1a
cp backend.hcl.example backend.hcl
# edit backend.hcl with the bootstrap outputs
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars if your region, repo, branch, or existing GitHub OIDC provider differ
terraform init -backend-config=backend.hcl
terraform plan
```

Do not auto-apply. The first `terraform plan` for Phase 1a should show creates
for the network, security groups, ALB, ECR repos, ECS cluster/task
definitions/services, RDS instance, log groups, alarms, and GitHub deploy role.
It should not show any application events, queues, consumers, NAT gateway, or VPC
endpoints.

Important: ECS services start at desired count `0`. After Terraform creates the
infrastructure, GitHub Actions builds the app-provided images, registers new
task definition revisions, runs migrations, and scales services to `1`.

## Deploy pipeline and Alembic migrations

The deploy workflow is `.github/workflows/deploy-phase1a.yml`.

Migration order:

1. GitHub Actions assumes the Terraform-created AWS role through OIDC.
2. It builds and pushes the Next.js and FastAPI images to ECR.
3. It registers a new FastAPI ECS task definition revision using the new image.
4. It runs `alembic upgrade head` as a one-off Fargate task with the same
   subnets, security group, environment variables, and Secrets Manager injection
   as the FastAPI service.
5. It waits for that migration task to stop and checks the container exit code.
6. Only if migrations succeed, it updates the long-running FastAPI ECS service.
7. It updates the Next.js ECS service.

This keeps the GitHub runner away from the database network and away from
plaintext database credentials. The tradeoff is that migrations must remain
deploy-safe: destructive or backward-incompatible schema changes need a planned
expand/contract sequence.
