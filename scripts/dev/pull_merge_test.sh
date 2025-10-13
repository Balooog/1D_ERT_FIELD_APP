#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../../"  # repo root (scripts/dev → repo)
echo "[pull] Stashing any WIP…"
git stash push -u -m "WIP before pull" || true

echo "[pull] Fetching remotes…"
git fetch --all --prune

echo "[pull] Updating main…"
git checkout main
git pull --rebase origin main

echo "[pull] Restoring WIP (if any)…"
git stash pop || echo "No stash to pop."

echo "[test] Running deps + CI loop…"
export PATH="$HOME/flutter/bin:$PATH"
flutter pub get
bash scripts/ci/test_wsl.sh

echo "[run] Optional Linux build & run (comment out if not needed)…"
flutter build linux && flutter run -d linux || true

echo "[done] Pull + test complete."
