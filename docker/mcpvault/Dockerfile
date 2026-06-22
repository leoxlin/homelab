# mcpvault
# Bridges the stdio-only @bitbonsai/mcpvault MCP server to Streamable HTTP so
# it can be consumed remotely at obsidian.hydrahmlb.cc/mcp.
FROM node:24-trixie-slim

# renovate: datasource=npm depName=supergateway
ARG SUPERGATEWAY_VERSION=3.4.3
# renovate: datasource=npm depName=@bitbonsai/mcpvault
ARG MCPVAULT_VERSION=0.12.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g \
    "supergateway@${SUPERGATEWAY_VERSION}" \
    "@bitbonsai/mcpvault@${MCPVAULT_VERSION}" \
  && npm cache clean --force

ENV NODE_ENV=production \
    PORT=3001

# node:24-trixie-slim ships a non-root `node` user (uid/gid 1000) to match
# the Obsidian deployment's fsGroup/ownership.
USER node
WORKDIR /data
EXPOSE 3001

CMD ["supergateway", \
  "--stdio", "npx -y @bitbonsai/mcpvault /data", \
  "--outputTransport", "streamableHttp", \
  "--port", "3001", \
  "--streamableHttpPath", "/mcp", \
  "--healthEndpoint", "/healthz"]
