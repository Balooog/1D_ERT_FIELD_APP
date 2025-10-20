#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Install or remove the ResiCheck pre-push secret scan hook.

Usage:
  scripts/git-hooks/install.sh [--install] [--force]
  scripts/git-hooks/install.sh --uninstall
EOF
  exit "${1:-0}"
}

action="install"
force=false

for arg in "$@"; do
  case "$arg" in
    --install)
      action="install"
      ;;
    --uninstall)
      action="uninstall"
      ;;
    --force)
      force=true
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      printf 'error: unknown option: %s\n\n' "$arg" >&2
      usage 1
      ;;
  esac
done

repo_root=$(git rev-parse --show-toplevel)
hook_dir="$repo_root/.git/hooks"
hook_path="$hook_dir/pre-push"
managed_marker="# ResiCheck pre-push hook (managed)"

if [[ "$action" == "uninstall" ]]; then
  if [[ -f "$hook_path" ]]; then
    if grep -q "$managed_marker" "$hook_path"; then
      rm -f "$hook_path"
      printf 'Removed managed pre-push hook.\n'
    else
      printf 'info: existing pre-push hook does not appear managed; not removing.\n'
    fi
  else
    printf 'info: no pre-push hook to remove.\n'
  fi
  exit 0
fi

mkdir -p "$hook_dir"

if [[ -f "$hook_path" && "$force" == false ]]; then
  if grep -q "$managed_marker" "$hook_path"; then
    printf 'info: pre-push hook already installed.\n'
    exit 0
  fi
  printf 'error: pre-push hook already exists. Re-run with --force to overwrite.\n' >&2
  exit 1
fi

cat >"$hook_path" <<EOF
#!/usr/bin/env bash
$managed_marker
set -euo pipefail
repo_root="\$(git rev-parse --show-toplevel)"
exec "\$repo_root/scripts/git-hooks/pre-push.sh" "\$@"
EOF

chmod +x "$hook_path"

printf 'Installed ResiCheck pre-push secret scan hook.\n'
