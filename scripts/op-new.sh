#!/bin/bash
set -euo pipefail

VAULT="${OP_VAULT:-Hydra}"
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  op-new.sh [options] <title>

Create a new 1Password Server item in the Hydra vault with all template
fields and template sections removed.

Options:
  --vault <vault>    1Password vault name. Default: Hydra, or OP_VAULT.
  --dry-run          Preview the item without creating it.
  -h, --help         Show this help.

Examples:
  scripts/op-new.sh my-secret
  scripts/op-new.sh --dry-run my-secret
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
  [[ $# -gt 0 ]] || {
    usage
    exit 1
  }

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --vault)
        [[ $# -ge 2 ]] || die "--vault requires a value"
        VAULT="$2"
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
        TITLE="${1}"
        shift
        ;;
    esac
  done

  [[ -n "${TITLE:-}" ]] || die "missing item title"
}

create_item() {
  local dry_run_flag=()

  if [[ "$DRY_RUN" -eq 1 ]]; then
    dry_run_flag=(--dry-run)
  fi

  jq -n --arg title "$TITLE" '{
    title: $title,
    category: "SERVER",
    sections: [],
    fields: []
  }' | op item create --vault "$VAULT" --format json "${dry_run_flag[@]}" -
}

main() {
  require_cmd op
  require_cmd jq
  parse_args "$@"
  create_item
}

main "$@"
