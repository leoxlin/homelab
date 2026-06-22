#!/usr/bin/env sh
set -e

PORT="${PORT:-3100}"
STREAMABLE_HTTP_PATH="${STREAMABLE_HTTP_PATH:-/mcp}"
HEALTH_ENDPOINT="${HEALTH_ENDPOINT:-/healthz}"

exec supergateway \
  --stdio "npx -y @karakeep/mcp" \
  --outputTransport streamableHttp \
  --port "$PORT" \
  --streamableHttpPath "$STREAMABLE_HTTP_PATH" \
  --healthEndpoint "$HEALTH_ENDPOINT" \
  "$@"
