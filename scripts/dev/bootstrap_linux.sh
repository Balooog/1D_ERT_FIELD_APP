#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This bootstrap script only supports Linux hosts." >&2
  exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
  echo "apt-get not found. Install dependencies manually for your distribution." >&2
  exit 1
fi

packages=(
  build-essential
  clang
  cmake
  ninja-build
  pkg-config
  libgtk-3-dev
  liblzma-dev
)

missing=()
for pkg in "${packages[@]}"; do
  if ! dpkg -s "$pkg" >/dev/null 2>&1; then
    missing+=("$pkg")
  fi
done

if [[ ${#missing[@]} -eq 0 ]]; then
  echo "All required Linux desktop dependencies are already installed."
else
  echo "Installing missing packages: ${missing[*]}"
  sudo_cmd=()
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    sudo_cmd=(sudo)
  fi
  "${sudo_cmd[@]}" apt-get update
  "${sudo_cmd[@]}" apt-get install -y "${missing[@]}"
fi

if command -v flutter >/dev/null 2>&1; then
  echo "Enabling Linux desktop support in Flutter."
  flutter --no-version-check config --enable-linux-desktop
else
  cat <<'EOF'
Flutter is not on PATH yet. After installing Flutter, run:
  flutter config --enable-linux-desktop
EOF
fi

echo "Linux desktop bootstrap complete."
