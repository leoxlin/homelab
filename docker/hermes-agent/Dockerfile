FROM nousresearch/hermes-agent:latest

RUN apt-get update \
 && apt-get install -y --no-install-recommends libolm3 libolm-dev build-essential cmake \
 && uv pip install --no-cache --python /opt/hermes/.venv/bin/python 'hermes-agent[matrix]' \
 && apt-get purge -y --auto-remove libolm-dev build-essential cmake \
 && rm -rf /var/lib/apt/lists/*

RUN cd /opt/hermes/scripts/whatsapp-bridge \
 && npm ci --silent --no-audit --no-fund

ARG SIGNAL_CLI_VERSION=0.14.4.1
RUN curl -fsSL "https://github.com/AsamK/signal-cli/releases/download/v${SIGNAL_CLI_VERSION}/signal-cli-${SIGNAL_CLI_VERSION}-Linux-native.tar.gz" \
      | tar -xz -C /usr/local/bin signal-cli \
 && chmod +x /usr/local/bin/signal-cli
