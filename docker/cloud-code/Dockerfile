# cloud-code
# Based on siteboon/claudecodeui, published as @cloudcli-ai/cloudcli.
# No upstream production image exists, so we build one from the npm package.
FROM node:22-bookworm-slim

# renovate: datasource=npm depName=@cloudcli-ai/cloudcli
ARG CLOUDCLI_VERSION=1.34.0
# renovate: datasource=npm depName=@anthropic-ai/claude-code
ARG CLAUDE_CODE_VERSION=2.1.177

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  ca-certificates \
  git \
  ripgrep \
  python3 \
  build-essential \
  && rm -rf /var/lib/apt/lists/* \
  && npm install -g \
  "@cloudcli-ai/cloudcli@${CLOUDCLI_VERSION}" \
  "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
  "node-pty@1.1.0" \
  && npm cache clean --force

# HOME=/data so both ~/.cloudcli (auth.db) and ~/.claude (session transcripts +
# OAuth creds) land on the mounted PVC and survive restarts.
ENV HOME=/data \
  SERVER_PORT=3001 \
  HOST=0.0.0.0

# The node:22 base ships a non-root `node` user (uid/gid 1000).
RUN mkdir -p /data && chown -R node:node /data
USER node
WORKDIR /data
VOLUME /data
EXPOSE 3001

CMD ["cloudcli", "start", "--port", "3001"]
