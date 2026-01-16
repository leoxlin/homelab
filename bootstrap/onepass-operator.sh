#!/bin/bash

eval $(echo 'export OP_TOKEN="op://Hydra/op-service-account-hydra-main/credential"' | op inject)
helm repo add 1password https://1password.github.io/connect-helm-charts/
helm \
  upgrade --install \
  connect 1password/connect \
  --namespace onepass-system \
  --create-namespace \
  --set operator.create=true \
  --set connect.create=false \
  --set operator.authMethod=service-account \
  --set operator.serviceAccountToken.value="$OP_TOKEN"
