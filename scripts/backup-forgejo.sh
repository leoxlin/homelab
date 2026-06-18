#!/bin/bash
set -euo pipefail

HOST="${FORGEJO_HOST:-falcon}"
DEST_DIR="${FORGEJO_BACKUP_DIR:-${HOME}/backups/forgejo}"
DRY_RUN=0
RESTARTED=0

REMOTE_DATA_DIR="/opt/forgejo/data"
REMOTE_COMPOSE_DIR="/opt/docker/compose/forgejo"
REMOTE_BACKUP_DIR="/tmp/forgejo-backups"

usage() {
  cat <<'EOF'
Usage:
  backup-forgejo.sh [options]

Back up the Forgejo deployment from the remote host to the local machine.
The script stops Forgejo briefly to ensure a consistent SQLite backup,
creates a tarball on the remote host, transfers it locally, and restarts
Forgejo.

Requires passwordless sudo or root SSH access on the remote host because
the Forgejo data directory is owned by root.

Environment variables:
  FORGEJO_HOST          SSH host or alias for the Forgejo server. Default: falcon
  FORGEJO_BACKUP_DIR    Local directory for backups. Default: ~/backups/forgejo

Options:
  --host <host>         SSH host or alias. Overrides FORGEJO_HOST.
  --dest <path>         Local backup directory. Overrides FORGEJO_BACKUP_DIR.
  --dry-run             Show what would be done without making changes.
  -h, --help            Show this help.
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --host)
        [[ $# -ge 2 ]] || die "--host requires a value"
        HOST="$2"
        shift 2
        ;;
      --dest)
        [[ $# -ge 2 ]] || die "--dest requires a value"
        DEST_DIR="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      -*)
        die "unknown option: $1"
        ;;
      *)
        die "unexpected argument: $1"
        ;;
    esac
  done
}

remote() {
  ssh -q "${HOST}" "$@"
}

ensure_restarted() {
  if [[ "${RESTARTED}" -eq 0 ]]; then
    echo "Ensuring Forgejo is restarted..."
    remote "cd ${REMOTE_COMPOSE_DIR} && sudo docker compose up -d" || true
    RESTARTED=1
  fi
}

main() {
  require_cmd ssh
  require_cmd rsync

  parse_args "$@"

  local timestamp
  timestamp="$(date +%Y%m%d-%H%M%S)"
  local archive_name="forgejo-backup-${timestamp}.tar.gz"
  local remote_archive="${REMOTE_BACKUP_DIR}/${archive_name}"
  local local_archive="${DEST_DIR}/${archive_name}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Dry run: would back up ${HOST}:${REMOTE_DATA_DIR} to ${local_archive}"
    exit 0
  fi

  echo "Checking SSH connectivity to ${HOST}..."
  remote "hostname" >/dev/null || die "cannot connect to ${HOST}"

  echo "Checking passwordless sudo access on ${HOST}..."
  remote "sudo -n true" >/dev/null 2>&1 || die "passwordless sudo is required for user on ${HOST}"

  echo "Creating local backup directory: ${DEST_DIR}"
  mkdir -p "${DEST_DIR}"

  # Ensure we restart Forgejo if anything fails after we stop it.
  RESTARTED=0
  trap ensure_restarted EXIT

  echo "Stopping Forgejo on ${HOST} for consistent backup..."
  remote "cd ${REMOTE_COMPOSE_DIR} && sudo docker compose down" || die "failed to stop Forgejo"

  echo "Creating remote archive: ${remote_archive}"
  remote "mkdir -p ${REMOTE_BACKUP_DIR} && \
    sudo tar czf ${remote_archive} -C / \
      ${REMOTE_DATA_DIR#/} \
      ${REMOTE_COMPOSE_DIR#/}"

  echo "Restarting Forgejo on ${HOST}..."
  remote "cd ${REMOTE_COMPOSE_DIR} && sudo docker compose up -d" || die "failed to restart Forgejo"
  RESTARTED=1

  echo "Transferring archive to local machine..."
  rsync -avz --progress "${HOST}:${remote_archive}" "${local_archive}"

  echo "Removing remote archive..."
  remote "rm -f ${remote_archive}"

  echo "Verifying local archive..."
  tar tzf "${local_archive}" >/dev/null || die "local archive is corrupt: ${local_archive}"

  echo "Backup complete: ${local_archive}"
  ls -lh "${local_archive}"
}

main "$@"
