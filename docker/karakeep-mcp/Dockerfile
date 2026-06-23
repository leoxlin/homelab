# karakeep-mcp
# Bridges the stdio-only @karakeep/mcp MCP server to Streamable HTTP so
# it can be consumed in-cluster by litellm.
FROM node:24-trixie-slim

# renovate: datasource=npm depName=supergateway
ARG SUPERGATEWAY_VERSION=3.4.3
# renovate: datasource=npm depName=@karakeep/mcp
ARG KARAKEEP_MCP_VERSION=0.32.0

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates \
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

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
