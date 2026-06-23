#!/usr/bin/env sh
set -eu

: "${PORT:=3100}"
: "${STREAMABLE_HTTP_PATH:=/mcp}"
: "${HEALTH_ENDPOINT:=/healthz}"
: "${SESSION_TIMEOUT:=1800000}"
: "${LOG_LEVEL:=none}"

exec supergateway \
  --stdio "${OBSIDIAN_MCP_COMMAND:-npx -y @bitbonsai/mcpvault /data}" \
  --outputTransport streamableHttp \
  --stateful \
  --sessionTimeout "$SESSION_TIMEOUT" \
  --port "$PORT" \
  --streamableHttpPath "$STREAMABLE_HTTP_PATH" \
  --healthEndpoint "$HEALTH_ENDPOINT" \
  --logLevel "$LOG_LEVEL" \
  "$@"
