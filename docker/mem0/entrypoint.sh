#!/bin/sh
set -e

MODE="${1:-server}"

case "$MODE" in
  server)
    cd /app/server
    API_HOST="${API_HOST:-0.0.0.0}"
    API_PORT="${API_PORT:-8000}"
    echo "Starting Mem0 API server on ${API_HOST}:${API_PORT}"
    alembic upgrade head
    exec uvicorn main:app --host "$API_HOST" --port "$API_PORT"
    ;;

  dashboard)
    cd /app/dashboard
    echo "Substituting NEXT_PUBLIC_* environment variables into the Next.js build"
    printenv | grep '^NEXT_PUBLIC_' | while IFS='=' read -r key value; do
      escaped=$(printf '%s' "$value" | sed -e 's/[\\&|]/\\&/g')
      find .next/ -type f -exec sed -i "s|$key|$escaped|g" {} \;
    done
    echo "Done replacing env variables NEXT_PUBLIC_ with real values"

    PORT="${PORT:-3000}"
    HOSTNAME="${HOSTNAME:-0.0.0.0}"
    echo "Starting Mem0 dashboard on ${HOSTNAME}:${PORT}"
    exec node server.js
    ;;

  *)
    echo "Unknown mode: $MODE. Use 'server' or 'dashboard'." >&2
    exit 1
    ;;
esac
