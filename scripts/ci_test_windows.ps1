# ResiCheck CI Test Runner (Windows)
$ErrorActionPreference = "Stop"
Write-Host "==> flutter pub get"
flutter pub get

Write-Host "==> dart format check"
dart format . --set-exit-if-changed

Write-Host "==> flutter analyze"
flutter analyze

Write-Host "==> flutter test (excluding widget_dialog)"
flutter test -x widget_dialog --reporter expanded

Write-Host "✅ CI test runner completed successfully"
