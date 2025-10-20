#!/usr/bin/env bash

# Abort on errors, unset vars, and pipeline failures.
set -euo pipefail

if [[ "${RESICHECK_SKIP_SECRET_SCAN:-0}" == "1" ]]; then
  printf 'info: RESICHECK_SKIP_SECRET_SCAN=1, skipping secret scans.\n'
  exit 0
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

ZEROS=0000000000000000000000000000000000000000
exit_code=0
git_secrets_available=0
git_secrets_missing_notice=0
declare -A scanned_paths=()

if git secrets --version >/dev/null 2>&1; then
  git_secrets_available=1
else
  git_secrets_missing_notice=1
fi

read_input=false
while IFS=' ' read -r local_ref local_sha remote_ref remote_sha; do
  read_input=true
  # Deleting refs (local SHA all zeros) or annotated tags do not need scanning.
  if [[ "${local_sha:-$ZEROS}" == "$ZEROS" ]]; then
    continue
  fi

  rev_list_args=("$local_sha")
  if [[ "${remote_sha:-$ZEROS}" != "$ZEROS" ]]; then
    rev_list_args+=("--not" "$remote_sha")
  fi

  while IFS= read -r commit; do
    [[ -z "$commit" ]] && continue

    while IFS= read -r path; do
      [[ -z "$path" ]] && continue

      # Ignore binary blobs flagged by git (diff-tree prefixes path with ":").
      if [[ "$path" == ":"* ]]; then
        continue
      fi

      # Inspect the committed file contents for private key markers.
      match=$(
        git show "${commit}:${path}" 2>/dev/null \
          | LC_ALL=C grep -En '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----' \
          || true
      )
      if [[ -n "$match" ]]; then
        printf '\nerror: potential private key detected before push\n'
        printf '  commit: %s\n' "${commit:0:12}"
        printf '  path:   %s\n' "$path"
        printf '%s\n' "$match" | sed 's/^/    /'
        exit_code=1
      fi

      if [[ "$git_secrets_available" -eq 1 ]]; then
        if [[ -z "${scanned_paths[$path]+set}" ]]; then
          if ! git secrets --scan -- "$path"; then
            printf '\nerror: git-secrets detected forbidden pattern before push\n'
            printf '  commit: %s\n' "${commit:0:12}"
            printf '  path:   %s\n' "$path"
            exit_code=1
          fi
          scanned_paths["$path"]=1
        fi
      fi
    done < <(git diff-tree --diff-filter=AM --no-commit-id --name-only -r "$commit")
  done < <(git rev-list "${rev_list_args[@]}")
done

# If the hook is invoked without push metadata, still be harmless.
if [[ "$read_input" == false ]]; then
  exit 0
fi

if [[ "$exit_code" -ne 0 ]]; then
  cat <<'EOF'

To bypass (not recommended), set RESICHECK_SKIP_SECRET_SCAN=1 for the push.
Investigate the listed files and strip any private keys or rotate credentials
before retrying the push.
EOF
elif [[ "$git_secrets_missing_notice" -eq 1 ]]; then
  cat <<'EOF'
info: git-secrets not detected on PATH; install it for additional regex-based secret scanning.
  scripts/security/git-secrets-setup.sh  # configure once installed
EOF
fi

exit "$exit_code"
