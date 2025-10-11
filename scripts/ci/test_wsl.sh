#!/usr/bin/env bash
set -euo pipefail
mkdir -p buildlogs
flutter pub get
dart format . --fix
flutter analyze | tee buildlogs/last_test.txt
flutter test -x widget_dialog | tee -a buildlogs/last_test.txt
