# Local LightCraft iPad development

Starting point: eliorodr2104/Unveil, commit 79be4e4 (native SwiftUI/Metal iPad adaptation).
Its vendored LightCraft engine is pinned in Engine/UPSTREAM.md. The current LightCraft
upstream is separately checked out in the parent folder for comparison.

Unveil already supplies local photo import, a native editor, ten basic adjustment controls,
background handling, and a Rust C ABI bridge. This is an existing adaptation, rather than
a newly created iPad port. Upstream baseline reports are author evidence, not local validation.
The full desktop LightCraft interface is not exposed by this native interface.

## Build

Install the Rust aarch64-apple-ios and aarch64-apple-ios-sim targets, then run:

```sh
scripts/build-xcframework.sh
scripts/build-ipad-local.sh 'id=YOUR_DEVICE_UDID'
```

APPLE_TEAM_ID and IPAD_BUNDLE_ID override the local defaults. The build uses a separate
com.cwallyman.LightCraftiPad identity, preserving the original project settings.
Build does not install or launch. The Rust build generates the device and simulator slices.

## First verification milestone

- Compile the Rust engine and Swift app locally.
- Run the existing bridge and app tests.
- Install on the paired iPad and verify opening a synthetic JPEG, exposure adjustment,
  background/foreground recovery, and persisted edits after relaunch.
- Inspect landscape and portrait layout and finger/Pencil input on the device.
- Check export availability before relying on this as a photo workflow.

Preserve originals. Use synthetic fixtures until the basic import/edit/relaunch path is verified.

The existing test suites can be run with `scripts/verify-ipad-local.sh`.

The first signed build found no Xcode account and no increased-memory profile. For a small
fixture prototype only, `IPAD_BASIC_SIGNING=1 scripts/build-ipad-local.sh` builds unsigned and
signs with the locally installed wildcard development profile. This mode omits the increased
memory entitlement; large RAW memory behavior needs separate testing. IPAD_PROFILE_PATH and
IPAD_SIGNING_IDENTITY override machine-specific defaults. The project capabilities stay intact.

## Local verification, 2026-10-16

- Both Rust engine release slices built (device and simulator).
- Rust bridge suite: 65 passed, 0 failed.
- Device Swift app built and signed with the basic profile; physical install timed out.
- Simulator build initially failed on CAMetalDrawable.drawableID. The canvas now omits
  drawable IDs from simulator diagnostics; the device path retains the original IDs.
- Device visual, Pencil, large RAW, and relaunch verification remain pending.

After the iPad was unlocked, installation succeeded. The first launch exposed a missing
signature on Xcode's debug dylib; the signing helper now signs those libraries before the
app bundle. Reinstall succeeded. App-side evidence confirms Apple M3 GPU (Metal), available,
and `measure: first full frame` for the bundled sample.jpg. A Photos access prompt appeared
over the editor; clean UI capture and hands-on input checks require dismissing it.
The simulator Swift build passed after the drawableID guard.

Final device check: user dismissed Photos access prompt. Clean landscape captures are in
../LocalVerification/ipad-editor-clean.png and ipad-adjustments.png. The latter shows exposure
+0.50 EV retained across termination/relaunch, the Edited label, histogram, and Light controls.
The view was visually inspected; hands-on finger/Pencil interaction and RAW memory tests remain
unverified. Work stays local on ipad-lightcraft; no new GitHub fork was created because an existing
native adaptation was found. No changes were pushed to either upstream repository.
