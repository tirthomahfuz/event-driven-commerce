# Web App

Phase 1a Next.js frontend for creating and fetching orders.

## API contract

The browser calls relative `/api/*` paths. In local development, Next.js rewrites
those calls to the order service using `NEXT_PUBLIC_API_BASE_URL`, defaulting to
`http://localhost:8000`. In AWS, the ALB routes `/api/*` to the order service, so
the same relative browser paths work.

## Local development

Install dependencies:

```bash
npm install
```

Run the app on port 3000:

```bash
NEXT_PUBLIC_API_BASE_URL=http://localhost:8000 npm run dev
```

Open `http://localhost:3000`.

## Production build without Docker

```bash
npm run build
PORT=3000 HOSTNAME=0.0.0.0 npm run start
```

## Docker build and run

The container listens on port 3000 to match the Phase 1a infra contract.

```bash
docker build -t event-commerce-web .
docker run --rm -p 3000:3000 \
  -e NEXT_PUBLIC_API_BASE_URL=http://host.docker.internal:8000 \
  event-commerce-web
```

If your local order service runs somewhere else, change
`NEXT_PUBLIC_API_BASE_URL` accordingly. Do not put secrets in this environment;
the browser app makes no AWS calls and only talks to the order API through
relative `/api/*` routes.
