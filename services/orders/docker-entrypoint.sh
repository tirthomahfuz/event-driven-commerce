#!/bin/sh
# Single image, two roles. The same built image serves the API by default and
# runs migrations when invoked with the `migrate` verb (CI/one-off task uses a
# command override). Any other argument is exec'd as-is, so a raw
# `alembic upgrade head` or a debug shell still works.
set -eu

cmd="${1:-api}"

case "$cmd" in
  api)
    exec uvicorn app.main:app --host 0.0.0.0 --port "${APP_PORT:-8000}"
    ;;
  migrate)
    exec alembic upgrade head
    ;;
  *)
    exec "$@"
    ;;
esac
