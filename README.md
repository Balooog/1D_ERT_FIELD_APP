# ResiCheck — 1D ERT Field App

ResiCheck (formerly VES QC) is a field-ready, offline-first Flutter companion for geophysicists validating 1-D ERT/VES soundings in real time.  It focuses on quick situational awareness, defensive QA, and rapid iteration while staying lightweight for remote use.

---

## Project workflow

The workspace provides autosaved project directories under `ResiCheckProjects/<ProjectName>/` with a left-pane plotting canvas and right-pane data-entry table optimized for tablet number pads.  Each project stores canonical `a` spacings, per-site metadata (power, stacks, soil, moisture), and dual-orientation readings (Direction A/B).

Key capabilities:

* Live log–log apparent-resistivity charts with site-average and ghost curves (static JSON, no AI dependencies)
* Deterministic QC flags (outlier cap, %SD gate, anisotropy ratio, log-jump) and DOI≈0.5 a depth cue
* Autosave every 10 s with undo/redo, keyboard shortcuts (`Ctrl+S`, `Ctrl+E`, `N`, `F`, `X`)
* Timestamped CSV + Surfer `.DAT` exports in each project’s `exports/` folder

---

## Repository layout

```
.
├── assets/                 # Sample CSVs, icons, and other bundled resources
├── lib/                    # Flutter application source
├── test/                   # Automated widget/unit tests
├── scripts/                # CI, bootstrap, and developer utilities
├── Makefile                # Helper targets for local dev loops
└── pubspec.yaml            # Flutter project manifest and dependencies
```

---

## 🚀 Quick Start (Fresh WSL Ubuntu)

These are the exact steps to get from a clean WSL (24.04 +) install to a working CLI build loop.

### 1️⃣ Clone and prepare the workspace

```bash
mkdir -p ~/code && cd ~/code
git clone https://github.com/Balooog/1D_ERT_FIELD_APP.git resicheck
cd resicheck
```

### 2️⃣ Add Flutter to PATH and verify

```bash
export PATH="$HOME/flutter/bin:$PATH"
flutter doctor -v
```

If Flutter reports missing Linux-toolchain components:

```bash
sudo apt update
sudo apt install -y cmake ninja-build pkg-config libgtk-3-dev \
  clang lld lldb build-essential liblzma-dev
```

### 3️⃣ Bootstrap the repo

```bash
flutter clean && flutter pub get
dart fix --apply && dart format .
dart analyze --no-fatal-warnings
flutter test -x widget_dialog
```

If you see “No Linux desktop project configured,” run once:

```bash
flutter create --platforms=linux .
git add linux .metadata && git commit -m "Add Linux desktop scaffold"
```

### 4️⃣ Local CLI loop (daily use)

```bash
git stash push -u -m "WIP"
git checkout main && git pull --rebase origin main
flutter clean && flutter pub get
dart fix --apply && dart format .
dart analyze --no-fatal-warnings
bash scripts/ci/test_wsl.sh
flutter build linux
flutter run -d linux    # requires WSLg (Win 11)
```

Confirm GUI availability:

```bash
echo $WAYLAND_DISPLAY || echo $DISPLAY
```

If blank, enable WSLg or install an X-server (VcXsrv/Xming).

---

## 🧩 Local Git Push & Branch Workflow

### In WSL (preferred)

```bash
git status -sb
git fetch --all --prune
git add .
git commit -m "fix: describe change"
git push -u origin feature/my-branch
```

If network fails (`Could not resolve host`):

```bash
echo "nameserver 1.1.1.1" | sudo tee /etc/resolv.conf
```

### From Windows (PowerShell)

```powershell
cd "\\wsl$\Ubuntu\home\axb\code\resicheck"
git config --global --add safe.directory "//wsl$/Ubuntu/home/axb/code/resicheck"
git push -u origin feature/my-branch
```

**SSH auth (recommended):**

```powershell
ssh-keygen -t ed25519 -C "your_email@example.com"
eval $(ssh-agent)
ssh-add ~/.ssh/id_ed25519
# Add the public key to GitHub → Settings → SSH Keys
git remote set-url origin git@github.com:Balooog/1D_ERT_FIELD_APP.git
git push -u origin feature/my-branch
```

**HTTPS + PAT auth:**

```powershell
git remote set-url origin https://github.com/Balooog/1D_ERT_FIELD_APP.git
git config --global credential.helper store
git push -u origin feature/my-branch
# Use GitHub username + Personal Access Token (repo scope)
```

---

## Quick build on Windows (PowerShell)

```powershell
cd C:\Users\abalo\Desktop\1D_ERT_FIELD_APP
$env:PATH += ";C:\src\flutter\bin"
git stash push -u -m "WIP"
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
```

---

## Getting started on Android (Android Studio / CLI)

*(section unchanged from previous version)*

---

## Features snapshot

*(unchanged)*

---

## License

MIT — see [LICENSE](LICENSE)
