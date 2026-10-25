#!/bin/bash
# Xcode Cloud starts from Git: prepare the ignored Rust framework and Core ML packages.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
export CARGO_HOME="$ROOT/.xcode-cloud/cargo"
export RUSTUP_HOME="$ROOT/.xcode-cloud/rustup"
export PATH="$CARGO_HOME/bin:$PATH"
mkdir -p "$ROOT/.xcode-cloud"

if [[ ! -x "$CARGO_HOME/bin/rustup" ]]; then
    curl --fail --location --proto '=https' --tlsv1.2 \
        https://sh.rustup.rs -o "$ROOT/.xcode-cloud/rustup-init.sh"
    sh "$ROOT/.xcode-cloud/rustup-init.sh" -y --no-modify-path \
        --profile minimal --default-toolchain 1.95.0
fi
rustup toolchain install 1.95.0 --profile minimal
rustup target add --toolchain 1.95.0 \
    aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-ios-macabi
export RUSTUP_TOOLCHAIN=1.95.0

# Python 3.12 has wheels for the pinned model-conversion dependencies.
export HOMEBREW_NO_AUTO_UPDATE=1
if ! brew list --versions python@3.12 >/dev/null 2>&1; then
    brew install python@3.12
fi
PYTHON="$(brew --prefix python@3.12)/bin/python3.12"
"$PYTHON" -m venv "$ROOT/.xcode-cloud/model-venv"
"$ROOT/.xcode-cloud/model-venv/bin/python" -m pip install \
    --only-binary=:all: -r scripts/mask-model-requirements.txt
"$ROOT/.xcode-cloud/model-venv/bin/python" scripts/build-mask-models.py
"$PYTHON" scripts/audit-branding.py
scripts/build-xcframework.sh

echo 'iLightCraft dependencies prepared for Xcode Cloud.'
