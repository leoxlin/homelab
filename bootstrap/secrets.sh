#!/bin/bash

kubectl create secret generic \
  cloudflare-api-token-secret \
  --from-literal=api-token="$(op item get --vault Hydra k3s-cert-manager-cloudflare-api-token --fields password --reveal)" \
  -n cert-manager
