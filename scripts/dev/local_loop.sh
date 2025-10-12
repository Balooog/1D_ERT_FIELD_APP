#!/usr/bin/env bash
set -euo pipefail

# 🧭 ResiCheck Local Dev Loop (no network, no git ops)

REPO_ROOT="${HOME}/code/resicheck"

if [[ ! -d "${REPO_ROOT}" ]]; then
  mkdir -p "${HOME}/code"
  cd "${HOME}/code"
  git clone https://github.com/Balooog/1D_ERT_FIELD_APP.git resicheck
  cd "${REPO_ROOT}"
else
  cd "${REPO_ROOT}"
fi

export PATH="${HOME}/flutter/bin:${PATH}"

flutter pub get

bash scripts/ci/test_wsl.sh

if flutter build linux; then
  flutter run -d linux
fi
