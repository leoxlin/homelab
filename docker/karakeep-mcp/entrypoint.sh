#!/usr/bin/env sh
set -eu

: "${PORT:=3100}"
: "${STREAMABLE_HTTP_PATH:=/mcp}"
: "${SESSION_TIMEOUT:=1800000}"
: "${LOG_LEVEL:=none}"

exec supergateway \
  --stdio "${KARAKEEP_MCP_COMMAND:-npx -y @karakeep/mcp}" \
  --outputTransport streamableHttp \
  --stateful \
  --sessionTimeout "$SESSION_TIMEOUT" \
  --port "$PORT" \
  --streamableHttpPath "$STREAMABLE_HTTP_PATH" \
  --logLevel "$LOG_LEVEL" \
  "$@"
