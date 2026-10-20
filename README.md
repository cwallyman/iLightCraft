# iLightCraft native Apple app

Native iPhone, iPad and Mac Catalyst photo editor, based on Unveil and the LightCraft Rust engine.

Repository: [cwallyman/iLightCraft](https://github.com/cwallyman/iLightCraft).
The same SwiftUI editor and UIKit/Metal canvas share the vendored LightCraft Rust engine
across iPad, iPhone and Mac Catalyst (Apple silicon). Minimum iOS/iPadOS 26;
Mac deployment compatibility and physical iPhone behavior still need verification.

The editor reserves separate space for the photo and adjustments: a compact bottom dock
on iPhone and narrow windows, and a 292-point side dock on iPad and Mac. Edit/Done is in
the top toolbar. Both layouts use tighter controls and a small histogram; the photo stays
visible while editing. Compact windows also stack the Photos browser controls.

## Build

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-ios-macabi
scripts/build-xcframework.sh
scripts/build-apple-local.sh simulator
scripts/build-apple-local.sh ios
scripts/build-apple-local.sh mac
```

These commands build unsigned local apps with `com.cwallyman.UnveilNative`, distinct from
both the previous iPad prototype and the web wrapper. Device installation requires signing; a development build was installed on the paired iPad and iPhone 17 Pro on 2026-10-19.
Mac development launch requires local signing. The XCFramework contains device, simulator
and Mac Catalyst arm64 libraries; Intel Mac support is not included yet.

The original local iPad signing scripts and identity remain available; see
[LOCAL-IPAD.md](Docs/LOCAL-IPAD.md) for the earlier device evidence.
See [verification notes](Docs/Verification/) for evidence and remaining device checks.

## Scope

The native feature queue is in [the prioritized plan](Docs/Plans/2026-10-19-lightroom-priorities.md),
starting with HEIC import, followed by export and the everyday editing workflow.

Native import, adjustments, undo/redo, before/after and the Metal canvas are joined by
JPEG/PNG/TIFF export with batch selection and native sharing, and More > Crop & Rotate
with crop handles, aspect presets, rotation, flips and straightening. The iPhone update was
installed and launched; the user confirmed export/crop. Native Apple RAW decoding, HDR gain-map
input, live float EDR display, HDR TIFF/HEIC export and same-item Apple Photos saving are now
implemented. More > HDR Editing controls HDR; More > Save to Apple Photos explicitly saves
Photos edits. Conflicts preserve local versions and offer reload. Camera support follows Apple's
decoder, and physical RAW/HDR/Photos round-trip acceptance remains pending. The wrapper's private CloudKit
sync has **not** been migrated. Existing wrapper
libraries remain in their own app; no automatic library conversion or deletion occurs.

Licensed under Apache-2.0; see `LICENSE` and `NOTICE`. Based on eliorodr2104/Unveil
at `79be4e4`, with the engine revision recorded in `Engine/UPSTREAM.md`.

## iLightCraft identity

The app uses LightCraft amber (#F2A516) and a floating winking lynx above its name.
Artwork provenance and licenses are in [asset attribution](assets/ATTRIBUTION.md).
The Xcode scheme and Swift module remain `Unveil` so existing build tooling and
local libraries keep working. The app display name is iLightCraft.

The source, saved regression tests and development notes are included here.
Build products, generated engine frameworks, provisioning profiles, real camera
fixtures, app-container backups and personal Photos libraries are not included.
Automated suites are saved for manual use; recent device and simulator builds
and visual checks are recorded separately in Docs/Verification.
