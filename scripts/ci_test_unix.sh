#!/usr/bin/env bash
set -euo pipefail

echo "==> flutter pub get"
flutter pub get

echo "==> dart format check"
dart format . --set-exit-if-changed

echo "==> flutter analyze"
flutter analyze

echo "==> flutter test (excluding widget_dialog)"
flutter test -x widget_dialog --reporter expanded

echo "✅ CI test runner completed successfully"
