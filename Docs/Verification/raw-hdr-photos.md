# Native RAW/HDR and Apple Photos editing

Last updated: 2026-10-19. Tasks U1.3/U1.4 (user list items 4 and 5).

## Implemented

- RAW imports from Files and Photos use Apple's full-resolution CIRAWFilter, with draft off,
  extended range enabled and the decoder version recorded. Unsupported cameras return an error;
  no embedded JPEG is silently substituted. Camera color comes from Apple's decoder.
- HDR gain maps expand natively; editing copies use linear half-float TIFF and keep their original
  source. Native import cleanup retains the original and provenance of every referenced raster.
- The Rust HDR tone/gamut path is backported from the local LightCraft reference. Live preview
  and zoom frames carry linear RGBA16F through bridge ABI 7 into an EDR CAMetalLayer. SDR frames
  retain their sRGB appearance through explicit transfer conversion. HDR buffers allocate lazily;
  allocation failure reports an error rather than claiming an SDR result is HDR.
- More > HDR Editing enables/disables HDR, with native undo/redo. Auto-enabled for native RAW/HDR
  editing copies. Output is bounded by the saved headroom (default 3 stops, at most 5).
- Export supports HDR 32-bit float TIFF and verified 10-bit PQ HEIC, with resizing, metadata
  choices, output sharpening and watermark applied by the shared Rust exporter before HEIC encoding.
  HDR HEIC encoding failures stop the operation; no SDR replacement is saved.
- Home's Files/Photos source choice is remembered. Files retains private local edits; Photos opens
  an asset's versioned content-editing input and exposes More > Save to Apple Photos.
- Same-item PhotoKit saves keep the original, full engine settings and Apple RAW decoder version.
  Existing local catalog edits are reused on reopen; a fresh device can restore supported saved settings.
- The asset revision and adjustment fingerprint are checked before save. A conflict keeps the local
  edit and offers Keep Local Edit or Reload Latest Photos Version. Reload archives its association
  and creates a distinct catalog version when necessary, preserving the previous draft for export.
- A successful PhotoKit commit is reported separately from a later cache/index update failure.
  Live Photos and video are explicitly rejected by this same-item workflow.

## Evidence and limits

Native Rust device/simulator/Mac Catalyst engine builds and iPhone/simulator app builds passed.
The iPhone simulator rendered the original generated chart with HDR Editing and +1 EV; its
capture was visually inspected. The screenshot is local-only at
`LocalVerification/ilightcraft-native-hdr-screen.png` in the parent workspace. The device build also
includes the subsequent native-HDR reset-default and memory-guard refinements.
Automated tests and benchmarks are saved for the user and were not run for this change.

Camera coverage follows the installed Apple RAW decoder; this is not universal RAW compatibility
or measured color parity with other photo editors. Input is capped at 80 megapixels with an available-memory
check before native decoding. Large files can still exceed a device's practical memory budget.
Actual EDR brightness depends on display support, brightness and current headroom. An SDR
screenshot cannot establish HDR brightness. Mac/iPad runtime and physical RAW/HDR/PhotoKit
round trips remain hands-on checks with disposable media and user-granted Photos access.

## Saved automated checks

From `NativeReference/Engine`:

```sh
cargo test --locked -p ilightcraft-ffi --test hdr_output
cargo test --locked -p ilightcraft-ffi --features test-hooks
```

Swift tests: `PhotosAdjustmentTests`, existing importer, import-cleanup, undo and canvas tests,
and the new native image-pipeline tests. Original hashes, saved settings, rendered HDR readback
and conflict/reload behavior should be checked in addition to compilation.

## User acceptance

- [ ] In Files, open the actual RAW camera files you use; inspect color, detail, rotation and zoom.
- [ ] Open a disposable HDR photo; compare HDR Editing on/off and change exposure/highlights.
- [ ] Export HDR TIFF and HEIC, then inspect them in another HDR-aware viewer.
- [ ] Choose Photos, grant access and open a disposable RAW/HDR/SDR photo.
- [ ] Edit/crop, choose More > Save to Apple Photos; confirm the same item changes, not a duplicate.
- [ ] Reopen/relaunch; verify sliders/crop and image appearance restore. Revert in Photos to confirm
  the original remains available. Verify the canonical original resource hash if running the audit.
- [ ] Change the disposable item in Photos while iLightCraft holds an edit; confirm save is blocked.
- [ ] Reload Latest Photos Version; verify the prior local version remains selectable for export.
- [ ] Check denial/limited access, iCloud download errors, offline state and low storage.

No personal-library edit or permission grant is performed by the agent for verification.

## iPhone delivery

The existing app container was backed up to the parent workspace's
`LocalVerification/device-backups/iphone-before-raw-hdr-photos-20261019`.
The final development-signed update was installed successfully on the paired iPhone 17 Pro
as `com.cwallyman.iLightCraft`, preserving app data. Launch was confirmed by devicectl.
Logs: `/tmp/ilightcraft-docked-device.log`, `/tmp/ilightcraft-sim-build.log`,
`/tmp/ilightcraft-raw-hdr-framework-final.log`, `/tmp/ilightcraft-raw-hdr-iphone-install.log`,
`/tmp/ilightcraft-raw-hdr-iphone-launch.log`. No automated suite or benchmark was run.

## ARW routing correction

The reported Sony ARW error exposed a native import routing gap. Camera extension detection
now supplements vendor UTI conformance and ImageIO type detection. Photos carries the explicit
RAW resource flag into import. Decoded TIFFs discard camera metadata so CFA/DNG tags cannot
route already decoded pixels back into the Rust RAW decoder. The working-copy cache version
is bumped to regenerate older transfers while retaining original files and drafts.
The Sony classification regression test is saved, not run. Actual affected ARW retry is pending.

The ARW correction passed the iPhone device build and was development-signed, installed and
launched successfully on the paired iPhone 17 Pro. App data was backed up first to
`LocalVerification/device-backups/iphone-before-arw-fix-retry-20261019` in the parent workspace.
No automated suite or affected-camera RAW decode was run by the agent.

## Photos save crash correction

The iPhone crash report `iLightCraft-2026-10-19-214007.ips` confirms SIGTRAP on
`com.apple.PHPhotoLibrary.transaction.high`. The stack enters
`_dispatch_assert_queue_fail`, Swift executor checking, then closure 2 in
`ApplePhotosEditor.save`. The Photos transaction callback inherited main-actor
isolation from the editor; PhotoKit executes it on its transaction queue.

The transaction and adjustment-data callbacks now explicitly use `@Sendable`
to prevent inherited main-actor isolation. UI state remains on the main actor.
No personal photo is automatically modified during agent verification.

Saved regression: `PhotosAdjustmentTests.saveSyntheticPhotoOnPhotosTransactionQueue`,
disabled unless `ILIGHTCRAFT_RUN_PHOTOS_SAVE_REGRESSION=1` is set in the test scheme.
It requires Photos access granted by the user to the test host, creates a 32-pixel
generated JPEG, saves an adjustment through the production path, verifies the same
asset and new revision, then deletes only its own generated asset. It was not run.
The device app build passed with the callback correction.

The corrected app was signed and installed successfully on the iPhone 17 Pro;
launch was confirmed by devicectl. The completed pre-update app-data backup is
`LocalVerification/device-backups/iphone-before-photos-save-fix-retry-20261019`
in the parent workspace. Actual save/reopen confirmation remains with the user.
