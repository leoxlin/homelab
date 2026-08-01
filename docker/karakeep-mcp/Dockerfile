# karakeep-mcp
# Bridges the stdio-only @karakeep/mcp MCP server to Streamable HTTP so
# it can be consumed in-cluster by litellm.
FROM node:24-trixie-slim

# renovate: datasource=npm depName=supergateway
ARG SUPERGATEWAY_VERSION=3.4.3
# renovate: datasource=npm depName=@karakeep/mcp
ARG KARAKEEP_MCP_VERSION=0.32.0

# tini runs as PID 1: supergateway spawns one stdio child per MCP session
# and never reaps them, so without an init they pile up as zombies until
# the container hits the fork limit (EAGAIN) and new sessions fail.
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates tini \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g \
    "supergateway@${SUPERGATEWAY_VERSION}" \
    "@karakeep/mcp@${KARAKEEP_MCP_VERSION}" \
  && npm cache clean --force

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENV NODE_ENV=production
ENV KARAKEEP_MCP_COMMAND=karakeep-mcp

# node:24-trixie-slim ships a non-root `node` user (uid/gid 1000).
USER node
WORKDIR /data

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
