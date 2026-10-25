#!/bin/bash
# Build the shared native editor using a separate identity from the web wrapper.
set -euo pipefail
cd "$(dirname "$0")/.."
for MODEL in SkySegSmall SkinSeg; do
    if [[ ! -d "iLightCraft/Resources/MaskModels/$MODEL.mlpackage" ]]; then
        echo 'Missing masking models. In a Python venv, install scripts/mask-model-requirements.txt and run scripts/build-mask-models.py.' >&2
        exit 1
    fi
done
PLATFORM="${1:-simulator}"
case "$PLATFORM" in
    simulator) DESTINATION='generic/platform=iOS Simulator' ;;
    ios) DESTINATION='generic/platform=iOS' ;;
    mac) DESTINATION='generic/platform=macOS,variant=Mac Catalyst' ;;
    *) echo 'usage: build-apple-local.sh [simulator|ios|mac]' >&2; exit 2 ;;
esac
[[ -d Frameworks/iLightCraftEngine.xcframework ]] || scripts/build-xcframework.sh
LOCAL_IDENTITY=()
if [[ -f Config/DevelopmentIdentity.xcconfig ]]; then
    LOCAL_IDENTITY=(-xcconfig Config/DevelopmentIdentity.xcconfig)
fi
BUNDLE_OVERRIDE=()
if [[ -n "${ILIGHTCRAFT_BUNDLE_ID:-}" ]]; then
    BUNDLE_OVERRIDE=("PRODUCT_BUNDLE_IDENTIFIER=$ILIGHTCRAFT_BUNDLE_ID")
fi
xcodebuild build "${LOCAL_IDENTITY[@]}" -project iLightCraft.xcodeproj -scheme iLightCraft \
    -configuration Debug -destination "$DESTINATION" \
    -derivedDataPath "DerivedData-Apple-$PLATFORM" \
    CODE_SIGNING_ALLOWED=NO \
    "${BUNDLE_OVERRIDE[@]}" \
    INFOPLIST_KEY_CFBundleDisplayName=iLightCraft
