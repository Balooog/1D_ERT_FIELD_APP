# VES QC — 1D ERT Field App

VES QC is a field-ready, offline-first Flutter companion for geophysicists validating 1-D ERT/VES soundings in real time. It focuses on quick situational awareness, defensive QA, and rapid iteration while staying lightweight for remote use.

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

## Getting started (brand-new Android & Flutter setup)

If you have never shipped an Android app before, work through each section in order. Every command runs from the repository root unless noted otherwise.

### 1. Install prerequisites

1. **Flutter SDK** (3.19 or newer)
   - Follow the official installation guide for your platform: <https://docs.flutter.dev/get-started/install>.
   - Extract Flutter, add `flutter/bin` to your system `PATH`, then restart your terminal.
2. **Android Studio**
   - Download from <https://developer.android.com/studio>.
   - During the first launch, keep the default components (Android SDK, Android SDK Platform, Android Virtual Device).
3. **Android command-line tools**
   - From Android Studio, open **More Actions → SDK Manager**.
   - Install at least one Android SDK platform (Android 14 or Android 13 recommended) and the **Android SDK Command-line Tools** package.
4. **Enable virtualization (for emulators)**
   - Windows: enable Hyper-V or Windows Hypervisor Platform via "Turn Windows features on or off".
   - macOS: Apple Silicon requires Rosetta + virtualization framework (usually already enabled).
5. **Git** (already included on macOS/Linux; Windows users can install from <https://git-scm.com/downloads>).

### 2. Verify your Flutter environment

```
flutter doctor
```

- Resolve every reported issue. For Android licenses, run:

```
flutter doctor --android-licenses
```

### 3. Clone the project

```
git clone https://github.com/Balooog/1D_ERT_FIELD_APP.git
cd 1D_ERT_FIELD_APP
```

### 4. Fetch dependencies and run static checks

```
flutter pub get
```

Optional but recommended checks:

```
flutter format .
flutter analyze
flutter test
```

### 5. Prepare a device

You need either a hardware Android device or an emulator.

- **Physical device**
  1. Enable *Developer options* (tap the build number 7 times in Settings → About phone).
  2. Turn on *USB debugging*.
  3. Connect via USB and accept the RSA fingerprint prompt.

- **Android emulator**
  1. Launch Android Studio → **More Actions → Virtual Device Manager**.
  2. Create a new device (Pixel 6 / Android 14 works well) and start it.

Verify that Flutter can see the device:

```
flutter devices
```

### 6. Run the app

```
flutter run
```

Hot reload is available with `r` (hot reload) or `R` (hot restart) while the command is running.

### 7. Build a release APK

```
flutter build apk --release
```

You will find the generated APK at `build/app/outputs/flutter-apk/app-release.apk`.

### 8. Common Makefile shortcuts

```
make dev   # flutter run with hot reload flags
make test  # flutter test
make apk   # flutter build apk --release
```

## Features snapshot

- **Live sounding chart** with log axes, error bars, and ±1σ inversion band.
- **Lite inversion** (3–5 layers) using damped least squares with smoothing.
- **Residual strip** highlighting normalized residuals against ±15% guidelines.
- **Telemetry panel** with 30-second sparklines for current, potential, and SP drift.
- **Traffic-light QA** per sounding and global badges for RMS%, χ², drift, and contact resistance.
- **Simulation mode** for training/validation and offline demonstrations.
- **CSV import/export** using the schema below.
- **Manual data entry** for ad-hoc measurements.

## CSV schema

A sample file lives at `assets/samples/sample_wenner.csv`.

| Column | Unit | Description |
| --- | --- | --- |
| `spacing_m` | m | Electrode spacing metric (a or AB/2). |
| `voltage_v` | V | Measured potential difference. |
| `current_a` | A | Injected current magnitude. |
| `array_type` | text | `wenner`, `schlumberger`, `dipole_dipole`, `pole_dipole`, or `custom`. |
| `mn_over_2_m` | m | Optional MN/2 spacing for Schlumberger geometries. |
| `rho_app_ohm_m` | Ω·m | Apparent resistivity. |
| `sigma_rho_app` | Ω·m | Standard deviation from repeats. |
| `timestamp_iso` | ISO8601 | Timestamp of acquisition. |

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
