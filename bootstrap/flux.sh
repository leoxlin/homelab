#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

helm upgrade --install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
  --namespace flux-system \
  --create-namespace \
  --version 0.38.1 \
  --wait

kubectl apply -f $SCRIPT_DIR/flux-secrets.yaml
kubectl apply -f $SCRIPT_DIR/flux-instance.yaml
