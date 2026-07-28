#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="${ROOT_DIR}/.tmp/phase1-local-smoke"
COMPOSE_FILE="${TMP_DIR}/docker-compose.yml"
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-phase1_smoke}"
NETWORK_NAME="${COMPOSE_PROJECT_NAME}_default"

POSTGRES_DB="${POSTGRES_DB:-orders}"
POSTGRES_USER="${POSTGRES_USER:-orders_app}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-orders_local_password}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
DATABASE_URL="postgresql+psycopg://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${POSTGRES_PORT}/${POSTGRES_DB}"

ORDERS_IMAGE="${ORDERS_IMAGE:-event-commerce-orders:local-smoke}"
ORDERS_CONTAINER="${ORDERS_CONTAINER:-phase1-orders-api-smoke}"
ORDERS_PORT="${ORDERS_PORT:-8000}"

PRODUCT_ID="${PRODUCT_ID:-00000000-0000-0000-0000-000000000001}"
PRODUCT_NAME="${PRODUCT_NAME:-Smoke Test Product}"
PRODUCT_PRICE_CENTS="${PRODUCT_PRICE_CENTS:-1299}"
PRODUCT_CURRENCY="${PRODUCT_CURRENCY:-USD}"
CUSTOMER_EMAIL="${CUSTOMER_EMAIL:-smoke@example.com}"

pass() {
  printf 'PASS %s\n' "$1"
}

fail() {
  printf 'FAIL %s\n' "$1"
  exit 1
}

run_step() {
  local label="$1"
  shift
  if "$@"; then
    pass "$label"
  else
    fail "$label"
  fi
}

cleanup() {
  docker rm -f "${ORDERS_CONTAINER}" >/dev/null 2>&1 || true
  if [ -f "${COMPOSE_FILE}" ]; then
    COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}" docker compose -f "${COMPOSE_FILE}" down -v >/dev/null 2>&1 || true
  fi
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

wait_for_postgres() {
  for _ in $(seq 1 60); do
    if COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}" docker compose -f "${COMPOSE_FILE}" exec -T postgres \
      pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_orders_api() {
  for _ in $(seq 1 60); do
    if curl -fsS "http://127.0.0.1:${ORDERS_PORT}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  docker logs "${ORDERS_CONTAINER}" || true
  return 1
}

psql_exec() {
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}" docker compose -f "${COMPOSE_FILE}" exec -T postgres \
    psql -v ON_ERROR_STOP=1 -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" "$@"
}

json_field() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get(sys.argv[1], ""))' "$1"
}

json_get() {
  python3 -c 'import json,sys; data=json.load(sys.stdin); path=sys.argv[1].split("."); cur=data
for part in path:
    if part.isdigit():
        cur=cur[int(part)]
    else:
        cur=cur[part]
print(cur)' "$1"
}

write_compose_file() {
  mkdir -p "${TMP_DIR}"
  cat >"${COMPOSE_FILE}" <<YAML
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: ${POSTGRES_DB}
      POSTGRES_USER: ${POSTGRES_USER}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    ports:
      - "${POSTGRES_PORT}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}"]
      interval: 2s
      timeout: 2s
      retries: 30
YAML
}

start_postgres() {
  write_compose_file
  COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}" docker compose -f "${COMPOSE_FILE}" up -d postgres
  wait_for_postgres
}

run_alembic_upgrade() {
  cd "${ROOT_DIR}/services/orders"
  DATABASE_URL="${DATABASE_URL}" alembic upgrade head
}

run_alembic_check() {
  cd "${ROOT_DIR}/services/orders"
  DATABASE_URL="${DATABASE_URL}" alembic check
}

build_orders_image() {
  docker build -t "${ORDERS_IMAGE}" "${ROOT_DIR}/services/orders"
}

prove_image_migrate_verb() {
  docker run --rm \
    --network "${NETWORK_NAME}" \
    -e DB_HOST=postgres \
    -e DB_PORT=5432 \
    -e DB_NAME="${POSTGRES_DB}" \
    -e DB_USERNAME="${POSTGRES_USER}" \
    -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
    "${ORDERS_IMAGE}" migrate
}

start_orders_api_from_image() {
  docker rm -f "${ORDERS_CONTAINER}" >/dev/null 2>&1 || true
  docker run -d \
    --name "${ORDERS_CONTAINER}" \
    --network "${NETWORK_NAME}" \
    -p "${ORDERS_PORT}:8000" \
    -e DB_HOST=postgres \
    -e DB_PORT=5432 \
    -e DB_NAME="${POSTGRES_DB}" \
    -e DB_USERNAME="${POSTGRES_USER}" \
    -e DB_PASSWORD="${POSTGRES_PASSWORD}" \
    "${ORDERS_IMAGE}" >/dev/null
  wait_for_orders_api
}

seed_product() {
  psql_exec <<SQL
insert into products (id, name, unit_price_cents, currency)
values ('${PRODUCT_ID}', '${PRODUCT_NAME}', ${PRODUCT_PRICE_CENTS}, '${PRODUCT_CURRENCY}')
on conflict (id) do update
set name = excluded.name,
    unit_price_cents = excluded.unit_price_cents,
    currency = excluded.currency;
SQL
}

order_count() {
  psql_exec -Atc "select count(*) from orders;"
}

post_order() {
  local idempotency_key="$1"
  local product_id="$2"
  local output_file="$3"
  local status_file="$4"

  curl -sS \
    -o "${output_file}" \
    -w '%{http_code}' \
    -X POST "http://127.0.0.1:${ORDERS_PORT}/api/orders" \
    -H 'content-type: application/json' \
    -H "Idempotency-Key: ${idempotency_key}" \
    -H "X-Request-Id: $(uuidgen | tr '[:upper:]' '[:lower:]')" \
    --data "{\"customer_email\":\"${CUSTOMER_EMAIL}\",\"items\":[{\"product_id\":\"${product_id}\",\"quantity\":1}]}" \
    >"${status_file}"
}

assert_create_and_replay() {
  local key
  key="$(uuidgen | tr '[:upper:]' '[:lower:]')"

  post_order "${key}" "${PRODUCT_ID}" "${TMP_DIR}/create.json" "${TMP_DIR}/create.status"
  [ "$(cat "${TMP_DIR}/create.status")" = "201" ] || return 1
  local order_id
  order_id="$(json_field id <"${TMP_DIR}/create.json")"
  [ -n "${order_id}" ] || return 1

  post_order "${key}" "${PRODUCT_ID}" "${TMP_DIR}/replay.json" "${TMP_DIR}/replay.status"
  [ "$(cat "${TMP_DIR}/replay.status")" = "200" ] || return 1
  local replay_order_id
  replay_order_id="$(json_field id <"${TMP_DIR}/replay.json")"
  [ "${order_id}" = "${replay_order_id}" ] || return 1

  printf '%s' "${order_id}" >"${TMP_DIR}/order_id"
}

assert_bogus_product_rejected() {
  local before_count after_count
  before_count="$(order_count)"
  post_order "$(uuidgen | tr '[:upper:]' '[:lower:]')" "ffffffff-ffff-ffff-ffff-ffffffffffff" "${TMP_DIR}/bogus.json" "${TMP_DIR}/bogus.status"
  [ "$(cat "${TMP_DIR}/bogus.status")" = "422" ] || return 1
  after_count="$(order_count)"
  [ "${before_count}" = "${after_count}" ]
}

assert_get_order_matches() {
  local order_id
  order_id="$(cat "${TMP_DIR}/order_id")"
  local status
  status="$(curl -sS -o "${TMP_DIR}/get.json" -w '%{http_code}' "http://127.0.0.1:${ORDERS_PORT}/api/orders/${order_id}")"
  [ "${status}" = "200" ] || return 1
  [ "$(json_field id <"${TMP_DIR}/get.json")" = "${order_id}" ] || return 1
  [ "$(json_field id <"${TMP_DIR}/create.json")" = "${order_id}" ] || return 1
  [ "$(json_get items.0.name <"${TMP_DIR}/get.json")" = "${PRODUCT_NAME}" ]
}

main() {
  trap cleanup EXIT
  require_command docker
  require_command curl
  require_command python3
  require_command uuidgen
  require_command alembic

  cleanup
  run_step "1 start local Postgres via docker-compose" start_postgres
  run_step "2 alembic upgrade head" run_alembic_upgrade
  run_step "3 alembic check has no diff" run_alembic_check
  run_step "4a build orders image" build_orders_image
  run_step "4b docker run image migrate succeeds" prove_image_migrate_verb
  run_step "4c bare image run serves on :8000" start_orders_api_from_image
  run_step "5 seed at least one product row" seed_product
  run_step "6 and 7 create order then replay same Idempotency-Key" assert_create_and_replay
  run_step "8 bogus product_id returns 422 and writes no order" assert_bogus_product_rejected
  run_step "9 GET order by id matches created order" assert_get_order_matches
  pass "10 local smoke test complete"
}

main "$@"
