# ResiCheck — 1D ERT Field App

ResiCheck (formerly VES QC) is a field-ready, offline-first Flutter companion for geophysicists validating 1-D ERT/VES soundings in real time. It focuses on quick situational awareness, defensive QA, and rapid iteration while staying lightweight for remote use.

## Project workflow (PR 026)

The project workspace now provides autosaved project directories under `ResiCheckProjects/<ProjectName>/` with a left-pane plotting canvas and right-pane data entry table optimised for tablet number pads. Each project stores canonical `a` spacings, per-site metadata (power, stacks, soil, moisture), and dual-orientation readings (Direction A/B). Key capabilities include:

- Live log–log apparent resistivity charts with site-average and template ghost curves (static JSON, no AI dependencies).
- Deterministic QC flags (outlier cap, %SD gate, anisotropy ratio, log-jump) plus a depth cue sketch using DOI ≈ 0.5a.
- Autosave every 10 s with undo/redo history, keyboard shortcuts (`Ctrl+S`, `Ctrl+E`, `N`, `F`, `X`) and a session-wide re-read history per spacing.
- Timestamped CSV and Surfer `.DAT` exports saved beneath each project's `exports/` folder.

A sample project (`assets/samples/sample_project.resicheck.json`) and ghost curve library (`assets/templates/ghost_curves.json`) are bundled for quick onboarding and offline validation.

## Repository layout

```
.
├── assets/                 # Sample CSVs, icons, and other bundled resources
├── lib/                    # Flutter application source
├── test/                   # Automated widget/unit tests
├── Makefile                # Helper commands for common Flutter workflows
├── pubspec.yaml            # Flutter project manifest and dependencies
└── analysis_options.yaml   # Lint configuration
```

## Data model & persistence

ResiCheck now centralizes survey data in `lib/models/project_models.dart` using
immutable, JSON-serializable types:

- `Project` → project-level metadata, canonical spacings, and `Site` entries.
- `Site` → unique sounding with paired `DirectionReadings` for directions A/B.
- `SpacingPoint` → individual spacing measurement including rho, exclusion flag,
  and operator note.

`lib/state/project_controller.dart` manages the active project/site selection,
data edits, and autosave throttling, while `lib/qc/qc.dart` computes residual
statistics against a log-linear model. Project files are saved under
`ResiCheckProjects/<name>.resicheck.json` via `lib/services/persistence.dart` and
load seamlessly on all supported platforms.

## Quick build on Windows (PowerShell)

```
cd C:\Users\abalo\Desktop\1D_ERT_FIELD_APP
$env:PATH += ";C:\src\flutter\bin"
git stash push -u -m "WIP"   # optional, avoids pull conflicts
git checkout main
git pull --rebase origin main
flutter clean
flutter pub get
dart format . --set-exit-if-changed
flutter analyze
flutter test -x widget_dialog
flutter config --enable-windows-desktop
flutter create --platforms=windows .
flutter run -d windows
# Test Build Complete
```

## Getting started

### Run on desktop

The first time you target Windows, enable the desktop tooling and regenerate the platform wrappers:

```
flutter config --enable-windows-desktop
flutter create --platforms=windows .
```

## Getting started on Android

### 1. One-time prerequisites

If this is your first Flutter + Android install, work through the list and check off each item before opening the project.

- **Flutter SDK** (3.19 or newer). Follow the platform guide at <https://docs.flutter.dev/get-started/install>, unzip the SDK, and add `flutter/bin` to your `PATH`.
- **Android Studio** with the default components (Android SDK, platform tools, and Android Virtual Device). Download from <https://developer.android.com/studio>.
- **Android SDK Platform + command-line tools.** In Android Studio open **More Actions → SDK Manager**, then install Android 14 (API 34) or Android 13 (API 33) and the "Android SDK Command-line Tools" package.
- **Virtualization** if you plan to use emulators. Enable Hyper-V or Windows Hypervisor Platform on Windows, and ensure Apple Virtualization is enabled/Rosetta installed on Apple Silicon Macs.
- **Git** (already available on macOS/Linux; Windows installers live at <https://git-scm.com/downloads>).

Run `flutter doctor` afterwards and accept any pending Android licenses with `flutter doctor --android-licenses`.

### 2. Project bootstrap

Clone the repository and pull dependencies:

```
git clone https://github.com/Balooog/1D_ERT_FIELD_APP.git
cd 1D_ERT_FIELD_APP
flutter pub get
```

Optional—but very helpful when you are editing code—run the built-in checks:

```
dart format .
flutter analyze
flutter test -x widget_dialog
```

### 3. Daily development workflow

```
flutter create .   # regenerate platform wrappers when missing
flutter run        # attach to a connected device or emulator
flutter build apk  # assemble a release APK

make dev           # convenience wrapper around flutter run
make test          # widget + unit tests
make apk           # release build
```

Hot reload stays available inside the `flutter run` session via `r` (reload) and `R` (restart).

### 4. Device & emulator setup

#### Samsung Tab Active4 Pro (field hardware)

We target the Samsung Tab Active4 Pro (Android 12/13, 10.1" 1920×1200) for on-site validation. To prepare a tablet:

1. Enable **Developer options** (Settings → About tablet → tap *Build number* seven times).
2. Inside **Developer options**, toggle **USB debugging** and (optionally) **Stay awake** to keep the display on while charging.
3. Under **Developer options → Input**, enable **Show taps** while testing glove/wet-touch gestures.
4. Connect over USB-C and accept the computer's RSA fingerprint prompt.
5. Confirm visibility with `flutter devices`. The output should list a device with `android-arm64` architecture.

Reference hardware highlights for the crew in the field:

| Spec / feature | Samsung Tab Active4 Pro |
| --- | --- |
| OS | Android 12 / 13 |
| Screen | 10.1", glove & wet-touch, 1920×1200 |
| Rugged rating | IP68, MIL-STD-810H |
| Hot-swappable battery | Yes (7,600 mAh equivalent) |
| Replaceable | Easy slide & swap |
| Weight | ~670 g (1.5 lbs) |
| Connectivity | Wi-Fi, optional LTE, Bluetooth |
| Built-in GNSS | GPS, GLONASS, BeiDou, Galileo |

The integrated GNSS is ideal for QA/inspection workflows even though it is not survey grade. Verify `Settings → Location` is enabled before heading to the field.

#### Emulator configuration (Samsung-class tablet)

1. Launch Android Studio → **More Actions → Virtual Device Manager**.
2. Create a **Tablet** profile. If the Tab Active4 Pro image is unavailable, the "Galaxy Tab S7 FE" or "Pixel Tablet" profile approximates the 10.1" 1920×1200 layout.
3. Choose a system image that matches field devices—Android 13 (API 33) works well because it aligns with the Tab Active4 Pro shipping version. Download the Google Play image so you can test location services and Play-dependent libraries.
4. Edit the hardware profile before creating the device: set RAM to **4 GB**, storage to **16 GB**, and enable **Use Host GPU** for responsive OpenGL rendering.
5. After the virtual device boots, open **Extended controls → Display** and set the resolution to **1920 × 1200**, 60 Hz, landscape orientation. Lock the orientation and disable automatic screen sleep under **Settings → Display** inside the emulator.
6. Configure sensors in **Extended controls → Settings**: enable **Multi-touch**, set **Pressure** to "Uniform," and toggle **Simulate wet fingers** to mimic the rugged tablet digitizer.
7. (Optional) In **Extended controls → Battery**, enable a custom profile (e.g., 40% with performance throttling) to validate hot-swap scenarios, and in **Location**, load GPX/KML tracks that match survey routes.

When the emulator is running, `flutter devices` should list an `android-x64` device. Launch the app with `flutter run`, press `M` to toggle multi-touch emulation, and use `Ctrl` + `Shift` + `L` (or `Cmd` + `Shift` + `L`) to rotate between landscape orientations.

## Features snapshot

- **Live sounding chart** with log axes, error bars, and ±1σ inversion band.
- **Lite inversion** (3–5 layers) using damped least squares with smoothing.
- **Residual strip** highlighting normalized residuals against ±15% guidelines.
- **Telemetry panel** with 30-second sparklines for current, potential, and SP drift.
- **Traffic-light QA** per sounding and global badges for RMS%, χ², drift, and contact resistance.
- **Simulation mode** for training/validation and offline demonstrations.
- **CSV import/export** using the schema below.
- **Manual data entry** for ad-hoc measurements.

> **Simulate note:** The Simulate button drives the UI with synthetic mock streams for demos and training; it does not compute an SP profile from your last manual point.

## Inversion visualisation & PDF export

- **Two-layer inversion plot.** The project workspace now includes an `InversionPlotPanel` that renders the best-fit two-layer profile with a colorblind-safe palette for layer contrast and overlays predicted vs observed curves alongside RMS context.
- **Single-site PDF export.** Use the site overflow menu to generate a report containing project metadata, a bitmap of the inversion panel, and a tabular breakdown of apparent vs fitted resistivities. Logs are written to `logs/export_*.txt` for audit trails.
- **Batch export.** The `File → Export All Sites to PDF` action assembles multi-page reports sorted by site name, mirroring the single-site layout while summarising RMS for each sounding.
- **Unit-aware formatting.** Exported reports automatically adopt the project's active distance unit (feet or metres) for spacing and depth, applying consistent rounding rules shared with the importer and table panels.

All PDF generation is implemented with the `pdf`/`printing` packages, keeping the app offline-first and requiring no platform-specific viewers.

## CSV schema

Sample CSV fixtures live at `assets/samples/Wenner1D.csv` and `assets/samples/Schlum1D.csv`.

| Column | Unit | Description |
| --- | --- | --- |
| `a_spacing_ft` | ft | Wenner A-spacing in feet (field input). |
| `a_spacing_m` | m | A-spacing converted to meters (export convenience). |
| `spacing_m` | m | Legacy spacing column; treated the same as `a_spacing_m` on import. |
| `rho_app_ohm_m` | Ω·m | Apparent resistivity captured in the field; recomputed during import if absent. |
| `sigma_rho_ohm_m` | Ω·m | Optional standard deviation for apparent resistivity. |
| `resistance_ohm` | Ω | Derived/legacy line resistance (exported for compatibility). |
| `resistance_std_ohm` | Ω | Derived standard deviation when `sigma_rho_ohm_m` is present. |
| `direction` | text | `ns`, `we`, or `other` (sounding orientation). |
| `voltage_v` | V | Optional potential measurement for QA (advanced). |
| `current_a` | A | Optional injected current for QA (advanced). |
| `array_type` | text | `wenner`, `schlumberger`, `dipole_dipole`, `pole_dipole`, or `custom`. |
| `timestamp_iso` | ISO8601 | Timestamp of acquisition. |

Legacy files that provide only `spacing_m`, `voltage_v`, and `current_a` are still accepted; ResiCheck derives `a_spacing_ft`, `rho_app_ohm_m`, and resistance terms automatically. Exports always include both feet and meter spacing columns for downstream workflows.

## Data import

ResiCheck 0.1 ships with a unified importer that recognises the most common field formats: delimited text (`.csv`, `.txt`), Surfer XYZ `.dat`, and Excel `.xlsx`. Any file can be mapped into the table entry workflow or merged into the active site.

- **Preview & column mapper.** After selecting a file the first 20 rows are shown alongside auto-detected column types (a-spacing, pins in/out, N–S / W–E resistances, and optional standard deviations). The mapper keeps one drop-down per column so you can override guesses on the fly.
- **Unit handling.** The importer inspects metadata rows (`Unit=...`), header suffixes (`_m`, `_ft`), and filenames (e.g. `*_m.csv`) to guess metres vs feet. The last unit you select is remembered for the session, and values are converted to feet internally for plots and QA badges.
- **Validation.** The importer reports how many rows were parsed, skipped, and why (NaN, negative spacing, duplicate a-spacing). Duplicate spacings can be overwritten when merging into an existing site.
- **Entry points.** From the Projects home screen use the overflow menu (`⋮`) or `Ctrl` + `I` to launch the importer, or open the "Add" menu inside a project to import into the active site.
- **Sample data.** Synthetic Wenner and Schlumberger CSV/DAT fixtures live under `test/data/import_samples/` with a README citing Loke. Excel workbooks are generated on the fly in tests to keep the repository binary-free.

Every import can either create a new site (with project defaults for stacks/power) or merge into the selected site. When merging, matching spacings prompt for overwrite; otherwise new spacings are appended and sorted.

## QA thresholds

- **GREEN**: CV ≤ 0.03 AND |r| ≤ 0.05
- **YELLOW**: 0.03 < CV ≤ 0.10 OR 0.05 < |r| ≤ 0.15
- **RED**: CV > 0.10 OR |r| > 0.15 OR |SP drift| > 5 mV OR contactR > 5000 Ω

Global header chips display RMS%, χ², counts of each color, most recent SP drift, and worst contact resistance observed.

## Offline-first notes

- No network calls or runtime permissions beyond local storage.
- State is kept in-memory and persisted with `shared_preferences` (wire-up for full session replay is underway).
- CSV exports default to the temp directory; adjust to your storage workflow.

## License

MIT — see [LICENSE](LICENSE).
