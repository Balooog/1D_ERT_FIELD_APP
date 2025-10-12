# ResiCheck — 1D ERT Field App

ResiCheck (formerly “VES QC”) is an offline-first Flutter companion for validating one-dimensional ERT/VES soundings in the field. The app emphasises quick QA, resilient data entry, and rugged-device ergonomics for teams running surveys in remote locations.

## Highlights

- Log–log sounding chart with model overlays, sigma bands, and tap-to-inspect points.
- Two-layer inversion summary with descriptive metrics (“Upper layer ρ”, “Layer thickness”, “RMS misfit”).
- Enlarged field entry table optimised for gloves/styli, with per-spacing notes and SD prompts.
- Residual strip, telemetry panel, autosave with undo/redo, and CSV/DAT/Excel import + export.
- Ghost-template overlay support (optional) with persistent project metadata (power, stacks, soil, moisture, ground temperature).

## Local Development

### Prerequisites

1. Flutter 3.19+ with desktop tooling enabled (`flutter config --enable-linux-desktop` or platform of choice).
2. Platform SDKs for any targets you intend to run (Android Studio/SDK for Android, Windows Desktop SDK, etc.).
3. Git, make (optional), and a recent Dart/Flutter-compatible IDE or editor.

### Fast local loop

The repository ships with a scripted test/build/run loop that mirrors the WSL CI harness:

```bash
scripts/dev/local_loop.sh
```

The script:

1. Clones/updates `~/code/resicheck` if missing.
2. Exports Flutter onto `PATH`.
3. Runs `flutter pub get`.
4. Executes the full analyzer/test sweep via `scripts/ci/test_wsl.sh`.
5. Builds the Linux desktop binary and launches it (`flutter build linux && flutter run -d linux`).

Use it from a fresh WSL window when you want the exact same checks as the CLI harness without touching Git history.

### Manual commands

If you prefer manual control, the essentials are:

```bash
flutter pub get
dart format . --set-exit-if-changed
flutter analyze
flutter test
flutter build linux   # or apk, ipa, windows, etc.
flutter run -d linux  # pick your device/emulator
```

The `scripts/ci/test_wsl.sh` helper wraps `dart format`, `flutter analyze`, and the project’s test matrix and is safe to run repeatedly.

## Repository Layout

```
.
├── assets/                 # Sample CSVs, ghost templates, icons
├── docs/                   # Supplemental guides (automation loop, usage notes)
├── lib/                    # Flutter source (state, UI, services)
├── scripts/                # CI/dev utilities (WSL loop, packaging)
├── test/                   # Unit + widget tests
├── Makefile                # Convenience aliases for common Flutter tasks
└── analysis_options.yaml   # Lint configuration
```

## Data Import & Export

- Import supports CSV/TXT, Surfer `.dat`, and Excel `.xlsx` with auto-mapped columns, unit inference, and validation before merge/create.
- Export generates CSV/DAT alongside PDF inversion summaries. Files land under the project’s autosave directory (`ResiCheckProjects/<ProjectName>/exports/`).
- Spacing values are stored internally in feet; formatting respects the active unit (feet/metres) using shared rounding utilities.

## Additional Documentation

- `docs/CODEX_TEST_LOOP.md` — background on the approved analyzer/test pipeline.
- `docs/IMPORTER.md` — format mapping rules and troubleshooting notes.
- `docs/CHANGELOG.md` — release history.

## License

MIT — see [LICENSE](LICENSE).
