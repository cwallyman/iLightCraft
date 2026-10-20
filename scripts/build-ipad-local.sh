#!/bin/bash
# Build this checkout with the local Apple team and a separate app identity.
set -euo pipefail
cd "$(dirname "$0")/.."
TEAM="${APPLE_TEAM_ID:-D58RZM4K8N}"
BUNDLE="${IPAD_BUNDLE_ID:-com.cwallyman.LightCraftiPad}"
DESTINATION="${1:-generic/platform=iOS}"
[[ -d Frameworks/UnveilEngine.xcframework ]] || scripts/build-xcframework.sh
SIGNING=()
if [[ "${IPAD_BASIC_SIGNING:-0}" == "1" ]]; then
    SIGNING=(CODE_SIGNING_ALLOWED=NO)
fi
xcodebuild build -project Unveil.xcodeproj -scheme Unveil \
    -configuration Debug -destination "$DESTINATION" \
    -derivedDataPath DerivedData-iPad -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$TEAM" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE" \
    INFOPLIST_KEY_CFBundleDisplayName=iLightCraft "${SIGNING[@]}"

if [[ "${IPAD_BASIC_SIGNING:-0}" == "1" ]]; then
    APPLE_TEAM_ID="$TEAM" IPAD_BUNDLE_ID="$BUNDLE" scripts/sign-ipad-local.sh
fi
