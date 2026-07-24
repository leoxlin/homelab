#!/usr/bin/env bash
set -euo pipefail

build_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checkout_dir="$(mktemp -d)"
trap 'rm -rf "$checkout_dir"' EXIT

git clone --depth 1 https://github.com/slopus/happy.git "$checkout_dir/happy"
git -C "$checkout_dir/happy" archive HEAD |
  tar --extract --directory="$build_dir" \
    --exclude=.gitignore \
    --exclude=Dockerfile \
    --exclude=setup-build.sh
