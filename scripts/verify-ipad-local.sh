#!/bin/bash
# Run the existing Rust bridge and Swift app tests for the local iPad prototype.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
(cd Engine && cargo test --locked -p ilightcraft-ffi --features test-hooks)
[[ -d Frameworks/iLightCraftEngine.xcframework ]] || scripts/build-xcframework.sh
scripts/test-app.sh
