#!/usr/bin/env bash
#
# Phase 1 local smoke test for the order service.
#
# Run this on YOUR machine (Docker + a working Python 3.12 are required).
# It is self-contained, idempotent, and re-runnable: it resets state at start
# and tears everything down on exit.
#
#   cd services/orders
#   ./scripts/smoke_test.sh
#
# What it does, in order:
#   1. Start local Postgres via docker-compose (postgres only).
#   2. Run `alembic upgrade head` against it (host venv).
#   3. Run `alembic check` and assert NO model/migration diff.
#   4. Build the orders image and prove BOTH verbs from that one image:
#      `docker run <image> migrate` succeeds, and a bare run serves on :8000.
#   5. Seed a product row.
#   6. POST /api/orders with an Idempotency-Key -> assert 201.
#   7. Replay the SAME Idempotency-Key -> assert 200 and same order id.
#   8. POST with a bogus product_id -> assert 422 and NO order row written.
#   9. GET the created order by id -> assert it matches.
#  10. Print a PASS/FAIL summary.
#
# Override defaults via env vars if needed (IMAGE, PROJECT, API_PORT).

set -uo pipefail

# --------------------------------------------------------------------------- #
# Config
# --------------------------------------------------------------------------- #
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SERVICE_DIR"

IMAGE="${IMAGE:-orders-smoke:latest}"
PROJECT="${PROJECT:-orders_smoke}"
NETWORK="${PROJECT}_default"
API_CONTAINER="${PROJECT}_api"
API_PORT="${API_PORT:-8000}"
BASE_URL="http://localhost:${API_PORT}"
VENV_DIR="$SERVICE_DIR/.smoke-venv"
BODY_FILE="$(mktemp)"

PRODUCT_SKU="SMOKE-WIDGET"
PRICE_CENTS=2500
QTY=2
EXPECTED_TOTAL=$((PRICE_CENTS * QTY))
IDEM_KEY="smoke-idem-key-1"
BOGUS_PRODUCT_ID="00000000-0000-0000-0000-000000000000"

DC() { docker compose -p "$PROJECT" "$@"; }

# --------------------------------------------------------------------------- #
# Pretty output + pass/fail tracking
# --------------------------------------------------------------------------- #
TOTAL=0
PASSED=0
declare -a RESULTS=()

c_green="$(printf '\033[32m')"; c_red="$(printf '\033[31m')"
c_bold="$(printf '\033[1m')"; c_reset="$(printf '\033[0m')"

step()  { printf '\n%s==> %s%s\n' "$c_bold" "$*" "$c_reset"; }
info()  { printf '    %s\n' "$*"; }
pass()  { TOTAL=$((TOTAL+1)); PASSED=$((PASSED+1)); RESULTS+=("${c_green}PASS${c_reset}  $1"); printf '    %sPASS%s %s\n' "$c_green" "$c_reset" "$1"; }
fail()  { TOTAL=$((TOTAL+1)); RESULTS+=("${c_red}FAIL${c_reset}  $1"); printf '    %sFAIL%s %s\n' "$c_red" "$c_reset" "$1"; }

# Abort on infrastructure failures we cannot recover from.
abort() { fail "$1"; printf '\n%sAborting: %s%s\n' "$c_red" "$1" "$c_reset"; summary; exit 1; }

jget() { python3 -c "import sys,json;print(json.load(open('$BODY_FILE')).get('$1',''))" 2>/dev/null; }

order_count() {
  DC exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
    "SELECT count(*) FROM orders;" 2>/dev/null | tr -d '[:space:]'
}

# --------------------------------------------------------------------------- #
# Teardown (runs on any exit) + initial reset
# --------------------------------------------------------------------------- #
cleanup() {
  step "Teardown"
  docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true
  DC down -v --remove-orphans >/dev/null 2>&1 || true
  docker rm -f orders-postgres >/dev/null 2>&1 || true
  rm -f "$BODY_FILE" >/dev/null 2>&1 || true
  info "stopped containers, removed volume."
}
trap cleanup EXIT

summary() {
  step "SUMMARY"
  if [ "${#RESULTS[@]}" -gt 0 ]; then
    for r in "${RESULTS[@]}"; do printf '    %s\n' "$r"; done
  fi
  printf '\n    %s%d/%d steps passed.%s\n' "$c_bold" "$PASSED" "$TOTAL" "$c_reset"
}

# --------------------------------------------------------------------------- #
# Preconditions
# --------------------------------------------------------------------------- #
command -v docker >/dev/null 2>&1 || { echo "docker is required"; exit 2; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required"; exit 2; }

if [ ! -f .env.local ]; then
  info ".env.local not found; creating it from .env.local.example"
  cp .env.local.example .env.local
fi

# Load local creds + DATABASE_URL (localhost form, used by host alembic).
set -a; . ./.env.local; set +a
HOST_DB_URL="$DATABASE_URL"
# In-container URL: reach the compose postgres service by name on the project network.
NET_DB_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}"

# Reset any prior run before we begin.
docker rm -f "$API_CONTAINER" >/dev/null 2>&1 || true
DC down -v --remove-orphans >/dev/null 2>&1 || true
docker rm -f orders-postgres >/dev/null 2>&1 || true

# --------------------------------------------------------------------------- #
# 1. Start Postgres
# --------------------------------------------------------------------------- #
step "1. Start local Postgres (docker-compose, postgres only)"
DC up -d || abort "docker compose up failed"
info "waiting for Postgres to be ready..."
ready=0
for _ in $(seq 1 30); do
  if DC exec -T postgres pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" >/dev/null 2>&1; then
    ready=1; break
  fi
  sleep 1
done
[ "$ready" = "1" ] && pass "Postgres is accepting connections" || abort "Postgres did not become ready"

# --------------------------------------------------------------------------- #
# 2. alembic upgrade head (host venv)
# --------------------------------------------------------------------------- #
step "2. Run migrations (alembic upgrade head)"
if [ ! -d "$VENV_DIR" ]; then
  python3 -m venv "$VENV_DIR" || abort "could not create venv (install the python3-venv package)"
fi
# shellcheck disable=SC1091
. "$VENV_DIR/bin/activate"
pip install -q --upgrade pip >/dev/null 2>&1
pip install -q -e . >/dev/null 2>&1 || abort "pip install of the order service failed"

export DATABASE_URL="$HOST_DB_URL"
if python -m alembic upgrade head; then
  pass "alembic upgrade head succeeded"
else
  abort "alembic upgrade head failed"
fi

# --------------------------------------------------------------------------- #
# 3. alembic check — assert NO diff
# --------------------------------------------------------------------------- #
step "3. Parity guard: alembic check (must report NO diff)"
check_out="$(python -m alembic check 2>&1)"
check_rc=$?
echo "$check_out" | sed 's/^/    /'
if [ "$check_rc" -eq 0 ]; then
  pass "alembic check reports no model/migration drift"
else
  fail "alembic check found drift (models are source of truth; fix the migration)"
fi

# --------------------------------------------------------------------------- #
# 4. Build image; prove BOTH verbs from the one image
# --------------------------------------------------------------------------- #
step "4. Build image and prove both verbs (migrate + api) from ONE image"
docker build -t "$IMAGE" . || abort "docker build failed"
info "image built: $IMAGE"

info "4a. docker run <image> migrate  (idempotent re-run of migrations)"
if docker run --rm --network "$NETWORK" -e DATABASE_URL="$NET_DB_URL" "$IMAGE" migrate; then
  pass "migrate verb works from the image"
else
  fail "migrate verb failed from the image"
fi

info "4b. bare run serves the API on :$API_PORT"
docker run -d --name "$API_CONTAINER" --network "$NETWORK" \
  -e DATABASE_URL="$NET_DB_URL" -p "${API_PORT}:8000" "$IMAGE" >/dev/null \
  || abort "could not start API container"
api_up=0
for _ in $(seq 1 30); do
  code="$(curl -s -o /dev/null -w '%{http_code}' "$BASE_URL/health" 2>/dev/null)"
  if [ "$code" = "200" ]; then api_up=1; break; fi
  sleep 1
done
if [ "$api_up" = "1" ]; then
  pass "bare run serves GET /health -> 200 on :$API_PORT"
else
  docker logs "$API_CONTAINER" 2>&1 | tail -20 | sed 's/^/    /'
  abort "API did not become healthy on :$API_PORT"
fi

# --------------------------------------------------------------------------- #
# 5. Seed a product
# --------------------------------------------------------------------------- #
step "5. Seed a product row"
PRODUCT_ID="$(DC exec -T postgres psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc \
  "INSERT INTO products (sku, name, price_cents, currency, stock_quantity)
   VALUES ('$PRODUCT_SKU', 'Smoke Widget', $PRICE_CENTS, 'USD', 100)
   ON CONFLICT (sku) DO UPDATE SET name = EXCLUDED.name
   RETURNING id;" 2>/dev/null | tr -d '[:space:]')"
if [ -n "$PRODUCT_ID" ]; then
  pass "seeded product $PRODUCT_ID (sku=$PRODUCT_SKU, price=$PRICE_CENTS)"
else
  abort "failed to seed product"
fi

# --------------------------------------------------------------------------- #
# 6. Create order (assert 201)
# --------------------------------------------------------------------------- #
step "6. Create order via POST /api/orders (assert 201)"
create_body="{\"customer_email\":\"smoke@example.com\",\"items\":[{\"product_id\":\"$PRODUCT_ID\",\"quantity\":$QTY}]}"
code="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$BASE_URL/api/orders" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $IDEM_KEY" -d "$create_body")"
ORDER_ID="$(jget id)"
ORDER_TOTAL="$(jget total_cents)"
if [ "$code" = "201" ] && [ -n "$ORDER_ID" ] && [ "$ORDER_TOTAL" = "$EXPECTED_TOTAL" ]; then
  pass "created order $ORDER_ID with total_cents=$ORDER_TOTAL (201)"
else
  fail "create order: expected 201/total=$EXPECTED_TOTAL, got code=$code total=$ORDER_TOTAL"
fi

# --------------------------------------------------------------------------- #
# 7. Replay same Idempotency-Key (assert 200 + same id)
# --------------------------------------------------------------------------- #
step "7. Replay same Idempotency-Key (assert 200 + same order id)"
code="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$BASE_URL/api/orders" \
  -H 'Content-Type: application/json' -H "Idempotency-Key: $IDEM_KEY" -d "$create_body")"
REPLAY_ID="$(jget id)"
if [ "$code" = "200" ] && [ "$REPLAY_ID" = "$ORDER_ID" ]; then
  pass "replay returned 200 with same id $REPLAY_ID (dedupe works)"
else
  fail "replay: expected 200/id=$ORDER_ID, got code=$code id=$REPLAY_ID"
fi

# --------------------------------------------------------------------------- #
# 8. Bogus product_id (assert 422 + no row written)
# --------------------------------------------------------------------------- #
step "8. Bogus product_id (assert 422 + transaction guard: no row written)"
count_before="$(order_count)"
bogus_body="{\"customer_email\":\"smoke@example.com\",\"items\":[{\"product_id\":\"$BOGUS_PRODUCT_ID\",\"quantity\":1}]}"
code="$(curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$BASE_URL/api/orders" \
  -H 'Content-Type: application/json' -d "$bogus_body")"
count_after="$(order_count)"
if [ "$code" = "422" ] && [ "$count_before" = "$count_after" ]; then
  pass "bogus product -> 422 and order count unchanged ($count_before == $count_after)"
else
  fail "bogus product: expected 422 + unchanged count, got code=$code before=$count_before after=$count_after"
fi

# --------------------------------------------------------------------------- #
# 9. GET order by id (assert match)
# --------------------------------------------------------------------------- #
step "9. GET /api/orders/{id} (assert it matches)"
code="$(curl -s -o "$BODY_FILE" -w '%{http_code}' "$BASE_URL/api/orders/$ORDER_ID")"
GOT_ID="$(jget id)"; GOT_TOTAL="$(jget total_cents)"
if [ "$code" = "200" ] && [ "$GOT_ID" = "$ORDER_ID" ] && [ "$GOT_TOTAL" = "$EXPECTED_TOTAL" ]; then
  pass "GET returned 200 with id=$GOT_ID total_cents=$GOT_TOTAL"
else
  fail "GET order: expected 200/id=$ORDER_ID/total=$EXPECTED_TOTAL, got code=$code id=$GOT_ID total=$GOT_TOTAL"
fi

# --------------------------------------------------------------------------- #
# 10. Summary
# --------------------------------------------------------------------------- #
summary
if [ "$PASSED" -eq "$TOTAL" ]; then exit 0; else exit 1; fi
