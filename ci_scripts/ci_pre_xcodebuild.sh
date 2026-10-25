#!/bin/bash
# Fail clearly if post-clone preparation was skipped or incomplete.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
for INPUT in Frameworks/iLightCraftEngine.xcframework \
    Config/iLightCraftEngine.xcconfig \
    iLightCraft/Resources/MaskModels/SkySegSmall.mlpackage \
    iLightCraft/Resources/MaskModels/SkinSeg.mlpackage; do
    if [[ ! -e "$ROOT/$INPUT" ]]; then
        echo "error: Missing $INPUT. Check the Xcode Cloud post-clone log." >&2
        exit 1
    fi
done
if [[ -f "$ROOT/Config/DevelopmentIdentity.xcconfig" ]]; then
    echo 'error: A local development identity must not be present in Xcode Cloud.' >&2
    exit 1
fi
