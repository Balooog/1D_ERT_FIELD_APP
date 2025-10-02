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
flutter format .
flutter analyze
flutter test
```

### 3. Daily development workflow

```
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
