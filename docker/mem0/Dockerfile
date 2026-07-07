# mem0
# Single image containing both the Mem0 FastAPI server and Next.js dashboard.

# renovate: datasource=docker depName=python
FROM python:3.12-slim@sha256:423ed6ab25b1921a477529254bfeeabf5855151dc2c3141699a1bfc852199fbf AS source

# renovate: datasource=github-releases depName=mem0ai/mem0
ARG MEM0_VERSION=v2.0.11

WORKDIR /src

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL "https://github.com/mem0ai/mem0/archive/refs/tags/${MEM0_VERSION}.tar.gz" \
    -o /tmp/mem0.tar.gz \
  && tar -xzf /tmp/mem0.tar.gz -C /src --strip-components=1 \
  && rm /tmp/mem0.tar.gz \
  && cp -a /src/server/dashboard /src/dashboard \
  && rm -rf /src/server/dashboard

# renovate: datasource=docker depName=node
FROM node:22-slim@sha256:813a7480f28fdadac1f7f5c824bcdad435b5bc1322a5968bbbdef8d058f9dff4 AS dashboard-builder

WORKDIR /app

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

COPY --from=source /src/dashboard/ ./

ENV NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_API_URL=NEXT_PUBLIC_API_URL \
    NEXT_PUBLIC_INSTANCE_NAME=NEXT_PUBLIC_INSTANCE_NAME

RUN if [ -f yarn.lock ]; then yarn --frozen-lockfile --network-timeout 600000 && yarn build; \
  elif [ -f package-lock.json ]; then npm ci && npm run build; \
  elif [ -f pnpm-lock.yaml ]; then corepack enable pnpm && pnpm install --frozen-lockfile && pnpm run build; \
  else echo "No lockfile found; aborting deterministic install." && exit 1; \
  fi

# renovate: datasource=docker depName=python
FROM python:3.12-slim@sha256:423ed6ab25b1921a477529254bfeeabf5855151dc2c3141699a1bfc852199fbf AS final

WORKDIR /app

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

LABEL org.opencontainers.image.title="mem0" \
      org.opencontainers.image.description="Single image containing both the Mem0 FastAPI server and Next.js dashboard" \
      org.opencontainers.image.source="https://github.com/mem0ai/mem0" \
      org.opencontainers.image.url="https://hub.docker.com/u/mem0"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HISTORY_DB_PATH=/app/history/history.db \
    NEXT_TELEMETRY_DISABLED=1 \
    NODE_ENV=production \
    API_HOST=0.0.0.0 \
    API_PORT=8000 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

# hadolint ignore=DL3008
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl gnupg libpq5 \
  && mkdir -p /etc/apt/keyrings \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_22.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# Install Python dependencies before copying the full server source so the layer
# cache is reused when only application code changes.
COPY --from=source /src/server/requirements.txt /app/server/requirements.txt
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    pip install --no-cache-dir -r /app/server/requirements.txt
COPY --from=source /src/server /app/server

# Copy dashboard runtime artifacts from the builder stage.
RUN mkdir -p /app/dashboard
COPY --from=dashboard-builder /app/public /app/dashboard/public
COPY --from=dashboard-builder /app/.next/standalone /app/dashboard
COPY --from=dashboard-builder /app/.next/static /app/dashboard/.next/static

# Unified entrypoint that dispatches to either the Mem0 API server or the
# Next.js dashboard based on the first positional argument.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN adduser --disabled-password --gecos "" mem0 \
  && mkdir -p /app/history \
  && chown -R mem0:mem0 /app

USER mem0

EXPOSE 8000 3000

# Default process is the Mem0 FastAPI server. The dashboard container overrides
# this command at runtime; Kubernetes probes are used for the dashboard.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --start-interval=5s --retries=3 \
  CMD bash -c 'exec 3<>/dev/tcp/127.0.0.1/${API_PORT:-8000}'

WORKDIR /app/server

ENTRYPOINT ["/entrypoint.sh"]
CMD ["server"]
