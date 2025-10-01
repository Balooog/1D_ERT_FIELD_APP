# VES QC

VES QC is a field-ready, offline-first Flutter companion for geophysicists validating 1-D ERT/VES soundings in real time. It focuses on quick situational awareness, defensive QA, and rapid iteration while staying lightweight for remote use.

## Why this matters

Vertical Electrical Soundings and 1-D Electrical Resistivity Tomography campaigns demand immediate QA to avoid costly rework. VES QC gives crews a mobile-first dashboard that:

- Streams measurements onto a log–log sounding curve with residual strip QA.
- Performs a lite Occam-style inversion on-device within seconds.
- Tracks telemetry (current, potential, SP drift, contact resistances) with traffic-light indicators.
- Works fully offline with deterministic simulation tools for dry runs.

## Features

- **Live sounding chart** with log axes, error bars, and ±1σ inversion band.
- **Lite inversion** (3–5 layers) using damped least squares with smoothing.
- **Residual strip** highlighting normalized residuals against ±15% guidelines.
- **Telemetry panel** with 30-second sparklines for current, potential, and SP drift.
- **Traffic-light QA** per sounding and global badges for RMS%, χ², drift, and contact resistance.
- **Simulation mode** for training/validation and offline demonstrations.
- **CSV import/export** using a straightforward schema (see below).
- **Manual data entry** for ad-hoc measurements.

### Screenshots

The automated build omits packaged images so the GPT web UI remains compatible. To generate a screenshot, run the simulator mode (`Simulate` toggle) on an emulator or device and capture the sounding dashboard manually.

## Data schema

CSV columns (`assets/samples/sample_wenner.csv` contains an example):

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

## Getting started

```bash
# Install Flutter (3.19+) and Android SDK prerequisites
flutter pub get

# Run analyzer and tests
flutter format .
flutter analyze
flutter test

# Launch on a connected device or emulator
flutter run

# Build a release APK
flutter build apk --release
```

### Makefile targets

A helper `Makefile` is provided:

```bash
make dev   # flutter run with --hot (debug)
make test  # flutter test
make apk   # flutter build apk --release
```

## Tests

Automated coverage includes:

- Geometry factor utilities
- QA classification rules
- Lite inversion sanity checks
- CSV import/export round-trips

Run them with `flutter test` (or `make test`).

## Offline-first notes

- No network calls or runtime permissions beyond local storage.
- State is kept in-memory and persisted with `shared_preferences` (to be wired for long-term session replay).
- CSV exports default to the temp directory; adjust to your storage workflow.

## License

MIT — see [LICENSE](../LICENSE).
