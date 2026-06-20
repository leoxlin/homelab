#!/bin/bash
set -euo pipefail

HOST="${FORGEJO_HOST:-apodemus}"
SOURCE=""
DRY_RUN=0

REMOTE_DATA_DIR="/opt/forgejo/data"
REMOTE_DATA_ARCHIVE_PATH="${REMOTE_DATA_DIR#/}"
REMOTE_RESTORE_DIR="/tmp/forgejo-restore"

usage() {
  cat <<'EOF'
Usage:
  restore-forgejo.sh [options] <backup-archive>

Restore the Forgejo data directory from a backup archive to the remote host.
The script extracts only opt/forgejo/data from the archive into /opt/forgejo/data
and removes the remote copy of the archive. It does NOT stop or start Forgejo;
stop the containers externally before running this script to avoid restoring
into a live, inconsistent data directory.

Requires passwordless sudo or root SSH access on the remote host because
the Forgejo data directory is owned by root.

Environment variables:
  FORGEJO_HOST          SSH host or alias for the Forgejo server. Default: apodemus

Options:
  --host <host>         SSH host or alias. Overrides FORGEJO_HOST.
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
        if [[ -z "${SOURCE}" ]]; then
          SOURCE="$1"
          shift
        else
          die "unexpected argument: $1"
        fi
        ;;
    esac
  done
}

remote() {
  ssh -q "${HOST}" "$@"
}

main() {
  require_cmd ssh
  require_cmd rsync

  parse_args "$@"

  if [[ -z "${SOURCE}" ]]; then
    usage >&2
    die "backup archive is required"
  fi

  if [[ ! -f "${SOURCE}" ]]; then
    die "backup archive not found: ${SOURCE}"
  fi

  local archive_name
  archive_name="$(basename "${SOURCE}")"
  local remote_archive="${REMOTE_RESTORE_DIR}/${archive_name}"

  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "Dry run: would restore ${SOURCE} to ${HOST}"
    exit 0
  fi

  echo "Checking SSH connectivity to ${HOST}..."
  remote "hostname" >/dev/null || die "cannot connect to ${HOST}"

  echo "Checking passwordless sudo access on ${HOST}..."
  remote "sudo -n true" >/dev/null 2>&1 || die "passwordless sudo is required for user on ${HOST}"

  echo "Verifying local archive: ${SOURCE}"
  tar tzf "${SOURCE}" >/dev/null || die "local archive is corrupt: ${SOURCE}"

  echo "Transferring archive to ${HOST}..."
  remote "mkdir -p ${REMOTE_RESTORE_DIR}"
  rsync -avz --progress "${SOURCE}" "${HOST}:${remote_archive}"

  echo "Restoring archive on ${HOST}..."
  remote "sudo tar xzf ${remote_archive} -C / ${REMOTE_DATA_ARCHIVE_PATH}" || die "failed to extract archive"

  echo "Removing remote archive..."
  remote "rm -f ${remote_archive}"

  echo "Restore complete on ${HOST}."
}

main "$@"
