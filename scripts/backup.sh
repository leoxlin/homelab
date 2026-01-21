#!/bin/bash
set -euo pipefail

APP="${1:-}"

if [[ -z "$APP" ]]; then
  echo "Usage: $0 <app>"
  echo "Available apps: immich, nextcloud"
  exit 1
fi

case "$APP" in
  immich|nextcloud)
    ;;
  *)
    echo "Unknown app: $APP"
    echo "Available apps: immich, nextcloud"
    exit 1
    ;;
esac

kubectl create -f - <<EOF
apiVersion: k8up.io/v1
kind: Backup
metadata:
  name: backup-${APP}-$(date +%Y%m%d-%H%M%S)
spec:
  failedJobsHistoryLimit: 10
  successfulJobsHistoryLimit: 10
  labelSelectors:
    - matchLabels:
        k8up.io/backup-target: ${APP}
  backend:
    repoPasswordSecretRef:
      name: k8up-secrets
      key: RESTIC_REPO_PASSWORD
    s3:
      endpoint: https://s3.eu-central-003.backblazeb2.com
      bucket: hydra-ecd4ffd5fcf8/backups/${APP}
      accessKeyIDSecretRef:
        name: k8up-secrets
        key: AWS_ACCESS_KEY_ID
      secretAccessKeySecretRef:
        name: k8up-secrets
        key: AWS_SECRET_ACCESS_KEY
EOF
