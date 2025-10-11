#!/usr/bin/env bash

set -euo pipefail

export FLUTTER_SUPPRESS_ANALYTICS=true

mkdir -p buildlogs

# Keep the workflow deterministic for Codex by formatting, analyzing, and testing in sequence.
dart format .
dart analyze | tee buildlogs/last_test.txt
flutter --no-version-check test -x widget_dialog | tee -a buildlogs/last_test.txt
