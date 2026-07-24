# lapdog
# Local LLM Observability dev tool — wraps dd-apm-test-agent.
# Based on the upstream Dockerfile at
# https://github.com/DataDog/dd-apm-test-agent/blob/master/Dockerfile
# but built from the GitHub release tarball so the image carries the exact
# Datadog release version.
FROM python:3.13-slim

# renovate: datasource=pypi depName=ddapm-test-agent
ARG LAPDOG_VERSION=1.63.1

WORKDIR /src

# The agent binds to loopback by default. In a container the published port is
# only reachable if the agent binds all interfaces, so opt in explicitly.
ENV HOST=0.0.0.0 \
    SNAPSHOT_CI=1 \
    LOG_LEVEL=INFO \
    SNAPSHOT_DIR=/snapshots \
    VCR_CASSETTES_DIRECTORY=/vcr-cassettes \
    SETUPTOOLS_SCM_PRETEND_VERSION_FOR_DDAPM_TEST_AGENT=${LAPDOG_VERSION}

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    git \
  && rm -rf /var/lib/apt/lists/* \
  && curl -fsSL \
    "https://github.com/DataDog/dd-apm-test-agent/archive/refs/tags/v${LAPDOG_VERSION}.tar.gz" \
    -o /tmp/lapdog.tar.gz \
  && tar -xzf /tmp/lapdog.tar.gz -C /src --strip-components=1 \
  && rm /tmp/lapdog.tar.gz \
  && pip install --no-cache-dir /src \
  && cp -r /src/vcr-cassettes /vcr-cassettes \
  && adduser --disabled-password --gecos "" lapdog \
  && mkdir -p /snapshots \
  && chown -R lapdog:lapdog /snapshots /vcr-cassettes

USER lapdog
WORKDIR /home/lapdog

VOLUME ["/snapshots", "/vcr-cassettes"]
EXPOSE 8126 4318 4317 9090

CMD ["ddapm-test-agent", "--lapdog-mode", "--disable-llmobs-data-forwarding", "--web-ui-port=9090"]
