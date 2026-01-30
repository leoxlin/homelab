#!/bin/bash

OP_CONNECT_TOKEN="$(op item get --vault Hydra main.1password --fields OP_CONNECT_TOKEN --reveal)"
op document get "main.1password.file" --vault Hydra --out-file 1password-credentials.json

helm repo add 1password https://1password.github.io/connect-helm-charts/
helm \
  upgrade --install \
  connect 1password/connect \
  --namespace onepass-system \
  --create-namespace \
  --set operator.create=true \
  --set connect.create=true \
  --set operator.token.value=$OP_CONNECT_TOKEN \
  --set-file connect.credentials=1password-credentials.json \

rm 1password-credentials.json
