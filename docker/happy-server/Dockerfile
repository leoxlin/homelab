# Happy Server is archived upstream without a published image, so build the
# documented server from its final commit.
# renovate: datasource=docker depName=node
FROM node:20-bookworm-slim AS builder

ARG HAPPY_SERVER_COMMIT=922a62fab5a6563ec0b636f3b26520e6bbec6af4

WORKDIR /app

ADD --checksum=sha256:b1765cfa0a6da66f0526f5f191f60ebc5cb7e7fe6def8aa16858b66f25823d60 \
  https://github.com/slopus/happy-server/archive/${HAPPY_SERVER_COMMIT}.tar.gz \
  /tmp/happy-server.tar.gz

RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential ffmpeg python3 \
  && rm -rf /var/lib/apt/lists/* \
  && tar -xzf /tmp/happy-server.tar.gz --strip-components=1 \
  && rm /tmp/happy-server.tar.gz \
  && yarn install --frozen-lockfile --ignore-engines \
  && yarn build

# renovate: datasource=docker depName=node
FROM node:20-bookworm-slim

WORKDIR /app

ENV NODE_ENV=production

RUN apt-get update \
  && apt-get install -y --no-install-recommends ffmpeg python3 \
  && rm -rf /var/lib/apt/lists/*

COPY --from=builder --chown=node:node /app/package.json /app/yarn.lock ./
COPY --from=builder --chown=node:node /app/node_modules ./node_modules
COPY --from=builder --chown=node:node /app/prisma ./prisma
COPY --from=builder --chown=node:node /app/sources ./sources
COPY --from=builder --chown=node:node /app/tsconfig.json ./

USER node

EXPOSE 3005

CMD ["yarn", "start"]
