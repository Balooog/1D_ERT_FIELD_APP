#!/usr/bin/env bash

set -euo pipefail

export FLUTTER_SUPPRESS_ANALYTICS=true

missing_tools=()
for tool in cmake ninja; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    missing_tools+=("$tool")
  fi
done

if [[ ${#missing_tools[@]} -gt 0 ]]; then
  printf 'error: missing required build tools: %s\n' "${missing_tools[*]}" >&2
  printf 'Install them via scripts/dev/bootstrap_linux.sh or your package manager.\n' >&2
  exit 1
fi

mkdir -p buildlogs

# Keep the workflow deterministic for Codex by formatting, analyzing, and testing in sequence.
dart format .
dart analyze --no-fatal-warnings | tee buildlogs/last_test.txt
flutter --no-version-check test -x widget_dialog | tee -a buildlogs/last_test.txt
