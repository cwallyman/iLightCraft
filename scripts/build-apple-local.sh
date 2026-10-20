#!/bin/bash
# Build the shared native editor using a separate identity from the web wrapper.
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM="${1:-simulator}"
case "$PLATFORM" in
    simulator) DESTINATION='generic/platform=iOS Simulator' ;;
    ios) DESTINATION='generic/platform=iOS' ;;
    mac) DESTINATION='generic/platform=macOS,variant=Mac Catalyst' ;;
    *) echo 'usage: build-apple-local.sh [simulator|ios|mac]' >&2; exit 2 ;;
esac
[[ -d Frameworks/UnveilEngine.xcframework ]] || scripts/build-xcframework.sh
xcodebuild build -project Unveil.xcodeproj -scheme Unveil \
    -configuration Debug -destination "$DESTINATION" \
    -derivedDataPath "DerivedData-Apple-$PLATFORM" \
    CODE_SIGNING_ALLOWED=NO \
    PRODUCT_BUNDLE_IDENTIFIER="${UNVEIL_BUNDLE_ID:-com.cwallyman.UnveilNative}" \
    INFOPLIST_KEY_CFBundleDisplayName=iLightCraft
