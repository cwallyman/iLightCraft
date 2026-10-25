#!/bin/bash
# Build a reviewable unsigned Release archive; never uploads, installs or launches.
set -euo pipefail
cd "$(dirname "$0")/.."
PLATFORM="${1:-ios}"
case "$PLATFORM" in
    ios) DESTINATION='generic/platform=iOS' ;;
    mac) DESTINATION='generic/platform=macOS,variant=Mac Catalyst' ;;
    *) echo 'usage: archive-apple-local.sh [ios|mac]' >&2; exit 2 ;;
esac
[[ -d Frameworks/iLightCraftEngine.xcframework ]] || scripts/build-xcframework.sh
xcodebuild archive -project iLightCraft.xcodeproj -scheme iLightCraft \
    -configuration Release -destination "$DESTINATION" \
    -archivePath "${ILIGHTCRAFT_ARCHIVE_PATH:-LocalVerification/Archives/iLightCraft-$PLATFORM.xcarchive}" \
    -derivedDataPath "DerivedData-Release-$PLATFORM" \
    CODE_SIGNING_ALLOWED=NO
