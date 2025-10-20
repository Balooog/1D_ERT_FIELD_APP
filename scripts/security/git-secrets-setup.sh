#!/usr/bin/env bash

# Configure git-secrets patterns for the ResiCheck repository.
set -euo pipefail

if ! command -v git >/dev/null 2>&1; then
  printf 'error: git is required but not found in PATH.\n' >&2
  exit 1
fi

if ! git secrets --version >/dev/null 2>&1; then
  cat <<'EOF' >&2
error: git-secrets is not installed.

Install it first (https://github.com/awslabs/git-secrets), then re-run:
  git clone https://github.com/awslabs/git-secrets.git
  cd git-secrets && sudo make install
EOF
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

printf 'Configuring git-secrets patterns for %s\n' "$repo_root"

# Register bundled AWS patterns (safe to run multiple times).
git secrets --register-aws

declare -a patterns=(
  "apikey_[0-9A-Za-z]{32}"
  "sk_live_[0-9a-zA-Z]{24}"
  "ssh-rsa [A-Za-z0-9+/]{100,}={0,3}"
)

current_patterns=$(git secrets --list || true)

for pattern in "${patterns[@]}"; do
  if printf '%s\n' "$current_patterns" | grep -Fq "$pattern"; then
    printf '  pattern already registered: %s\n' "$pattern"
    continue
  fi

  git secrets --add "$pattern"
  printf '  added pattern: %s\n' "$pattern"
done

cat <<'EOF'
Done. You can now run:
  git secrets --scan            # check working tree
  git secrets --scan-history    # optional full history audit

Tip: combine with scripts/git-hooks/install.sh to ensure pre-push scans also run git-secrets when available.
EOF
