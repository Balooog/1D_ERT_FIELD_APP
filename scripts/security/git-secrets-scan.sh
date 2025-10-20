#!/usr/bin/env bash

# Thin wrapper around `git secrets --scan` to provide consistent messaging.
set -euo pipefail

if ! git secrets --version >/dev/null 2>&1; then
  cat <<'EOF' >&2
error: git-secrets is not installed or not on PATH.
Install it via https://github.com/awslabs/git-secrets then retry.
EOF
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

printf 'Running git-secrets scan in %s\n' "$repo_root"

if [[ $# -gt 0 ]]; then
  git secrets --scan -- "$@"
else
  git secrets --scan
fi
