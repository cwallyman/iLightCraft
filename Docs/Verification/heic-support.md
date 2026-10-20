# HEIC support: saved work and manual verification

Last updated: 2026-10-19. Automated verification paused at the user's request to conserve credits.
Keep the saved tests for the user; do not resume expensive builds/tests unless requested.

## Implementation

- `Engine/ffi/Cargo.toml` enables the existing pure-Rust HEIC decoder through
  `lightcraft-codecs/heif` for all native app builds, without enabling AI features.
- Files already accepts image types; Photos already transfers original still-image resources
  through the same importer. The importer preserves the original bytes.
- No changes were made to the vendored decoder implementation.
- HEIC export, HDR gain maps and Live Photos remain separate roadmap tasks.

## Saved tests

- `Engine/ffi/tests/heic.rs`: decoder included in the native build; malformed HEIC rejected and
  the engine session remains usable for another import.
- `UnveilTests/HEICImportTests.swift`: runtime-generated Display P3 HEIC; upright and rotated
  orientations; import, rendered dimensions, exposure pixel change, reopen and original-byte
  preservation; malformed input followed by a successful import.

The decoder-inclusion regression was run before enabling the feature and failed as expected.
The first build attempts needed the existing pinned `heic-rs` dependency downloaded. Fetch
completed. Before verification was paused, the Rust bridge suite finished successfully and the
device, simulator and Mac Catalyst engine framework build completed. No Swift HEIC tests were run.
No passing HEIC app workflow or visual result is claimed here.

## iPhone update

The HEIC-enabled app and docked editor update built successfully and were development-signed,
then installed on the paired iPhone 17 Pro as `com.cwallyman.UnveilNative` on 2026-10-19.
The existing app container was backed up under the parent workspace's local
`LocalVerification/device-backups/iphone-before-heic-20261019` before installation.
HEIC import/editing remains a hands-on check for the user; saved Swift tests were not run.
Installation log: `/tmp/unveil-heic-iphone-install.log`.

## Commands for the user

From `NativeReference/Engine`:

```sh
cargo test --locked -p unveil-ffi --features test-hooks --test heic
```

From `NativeReference`, rebuild the engine framework before running Swift tests:

```sh
scripts/build-xcframework.sh
xcodebuild test -project Unveil.xcodeproj -scheme Unveil \
  -destination 'platform=iOS Simulator,id=5A52D08E-DD17-4C65-B84D-2170D3A2EC76' \
  -derivedDataPath DerivedData-HEIC CODE_SIGNING_ALLOWED=NO \
  PRODUCT_BUNDLE_IDENTIFIER=com.cwallyman.UnveilNative \
  -only-testing:UnveilTests/HEICImportTests
```

Simulator identifiers can change; use `xcrun simctl list devices available` if necessary.
The Swift tests require an HEIC encoder on the selected simulator. Encoder unavailability is a
verification limitation, not evidence that decoding works or fails.

## Hands-on checklist

- [ ] Install a freshly rebuilt app, preserving its existing data.
- [ ] Open HEIC from Files and Apple Photos.
- [ ] Check portrait/landscape orientation and color against the original.
- [ ] Adjust exposure and confirm the rendered photo changes.
- [ ] Close/reopen the photo; relaunch the app and verify edit persistence.
- [ ] Confirm originals remain unchanged and unsupported/corrupt input gives an actionable error.
- [ ] Record iPhone, iPad and Mac results separately.

## Existing local logs

- `/tmp/unveil-heic-before.log`: expected failing regression before enabling HEIC.
- `/tmp/unveil-heic-fetch.log`: dependency download.
- `/tmp/unveil-heic-rust.log`: Rust bridge suite attempt.
- `/tmp/unveil-heic-xcframework.log`: native engine framework build attempt.
- `/tmp/unveil-heic-fmt.log`: initial formatting check; the reported test formatting was corrected.

Priority queue: [Unveil feature priorities](../Plans/2026-10-19-lightroom-priorities.md).
