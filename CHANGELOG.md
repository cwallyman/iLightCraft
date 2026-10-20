# iLightCraft change history

Changes through 2026-10-19, relative to native Unveil `79be4e4`. First published implementation:
[`2f71fe9`](https://github.com/cwallyman/iLightCraft/commit/2f71fe9ad954352cdf0eec2ab64f765f56c0f3bc).
Implementation, delivery and acceptance are recorded separately.

## Apple platform foundation and layout

- Extended the native app to iPhone, iPad and Apple-silicon Mac Catalyst.
- Added the Mac Catalyst Rust slice, platform configuration and Mac entitlements.
- Retained SwiftUI, the UIKit/Metal canvas and the vendored LightCraft Rust engine.
- Added compact iPhone/narrow-window adjustments and a separate 292-point iPad/Mac side dock.
- Added top Edit/Done, tighter controls, compact histogram and compact Photos browser controls.
- Kept the photo viewport separate from adjustments and retained Files/Photos browsing.
- Added universal/local build, signing and verification helpers. Framework replacement stages
  the new framework and preserves the previous one instead of deleting it before a successful build.

## HEIC/HEIF import: U0.1

- Enabled the existing pure-Rust `lightcraft-codecs/heif` decoder in native bridge builds.
- Preserved source bytes through the shared Files/Photos importer.
- Saved decoder-inclusion, malformed-input, orientation, edit/reopen and preservation regressions.
- Delivered to iPhone; user accepted the milestone before requesting export/crop.

## Export and sharing: U1.1

- Added native JPEG, PNG and TIFF output through the shared Rust renderer/encoder.
- Exposed quality, resize, color-space/depth, metadata/location, sharpening and text watermark options.
- Added imported-photo batch selection, sequential progress and stop-after-current-photo behavior.
- Connected outputs to system sharing and Save to Files.
- Used unique temporary paths and refused to overwrite existing files or catalog originals.
- Added native bridge export commands and saved output regressions.

## Crop and straighten: U1.2

- Added More > Crop & Rotate, an uncropped preview, corner handles and crop positioning.
- Added free/original/square/4:5/5:7/2:3/4:3/16:9 presets and portrait/landscape selection.
- Added quarter-turn rotation, both flips and straightening up to 45 degrees in either direction.
- Kept drafts local until Done; Cancel preserves prior settings.
- Shared normalized crop geometry across preview/export, saved settings and native undo/redo.
- Explicitly cleared previous aspect locks when choosing free crop.
- Delivered export/crop to iPhone; user accepted the milestone.

## Native RAW/HDR: U1.3

- Added full-resolution Apple CIRAWFilter decoding with draft mode off and decoder-version provenance.
- Expanded supported HDR/gain-map input through Core Image before handing pixels to Rust.
- Retained original sources beside linear half-float TIFF editing copies and provenance records.
- Added size/available-memory guards and protected referenced originals during import cleanup.
- Backported bounded HDR tone/gamut behavior and float output into the vendored engine, preserving
  the SDR path and compatible settings serialization. Modification notices identify changed files.
- Extended bridge ABI to 7 for linear RGBA16F frames, with lazy HDR buffers and allocation errors.
- Added the EDR Metal canvas and explicit SDR transfer conversion.
- Added More > HDR Editing, undo/redo integration and native-import HDR reset defaults.
- Added HDR float TIFF export and native 10-bit PQ HEIC encoding with precision validation;
  failures report an error instead of silently producing SDR.
- Kept resize, metadata, sharpening and watermark processing in the shared output path.

## Apple Photos same-item editing: U1.4

- Added persistent content-editing source revisions and remembered home library selection.
- Stored complete supported engine settings and the RAW decoder version in Photos adjustment data.
- Reused mapped catalog drafts and restored supported settings for new working versions.
- Added explicit More > Save to Apple Photos with progress and actionable results/errors.
- Checked revisions/adjustment fingerprints before commit and detected external edits.
- Added Keep Local Edit / Reload Latest Photos Version, archived associations and preserved prior drafts.
- Distinguished a successful Photos commit from a subsequent local-cache update failure.
- Rejected Live Photos/video in this still-image editing workflow.

## Reported fixes

### Sony ARW import error

A Sony RAW reached the Rust RAW decoder instead of the native import path. Camera-extension
recognition now supplements UTI conformance and ImageIO type detection. Photos passes an explicit
RAW-source flag. Decoded TIFF transfers discard inherited RAW metadata to prevent reclassification
as RAW. The decoded-cache version changed so older transfers regenerate while originals/drafts remain.
The correction was built, installed and launched; affected-camera retry confirmation is pending.

### Crash saving to Photos

The device report showed a Swift actor-isolation trap in ApplePhotosEditor.save on PhotoKit's
transaction queue. The callback inherited main-actor isolation. Explicit @Sendable callbacks remove
that mismatch while UI state stays on the main actor. The correction was built, installed and
launched. Actual save/reopen confirmation is pending; an opt-in synthetic-asset regression is saved.

## iLightCraft branding

- Changed the display name and user-facing Photos messages to iLightCraft.
- Replaced purple accents with LightCraft amber-yellow, #F2A516.
- Replaced five floating photo cards with the existing winking lynx above the name.
- Added gentle Core Animation logo motion, pause behavior and Reduce Motion support.
- Added the matching app icon and artwork attribution/license files.
- Preserved existing app identity, library associations and internal scheme/module compatibility.
- Reviewed the simulator home and delivered the update to iPhone.

## GitHub and documentation

- Published the native app as cwallyman/iLightCraft, preserving the Unveil fork history/upstream remote.
- Set ipad-lightcraft as default branch and documented the full prioritized feature queue.
- Added saved regression tests, milestone evidence, asset provenance and vendored-engine notices.
- Excluded generated frameworks/builds, local backups, provisioning material and personal media.
- Expanded the README and added the comprehensive next-steps checklist and this change history.

## Evidence and limits

Device/simulator/Mac Catalyst engine builds passed. Recent iPhone/simulator app builds passed.
Signed iPhone updates were installed and launch confirmed; app data was backed up before updates.
Simulator crop, export, synthetic HDR and branding views were inspected.

The initial HEIC phase completed a Rust bridge suite before the user's request to leave testing
to them. Subsequent suites/benchmarks remain saved, unrun. HEIC and export/crop received general
user acceptance; detailed edge cases remain documented. Camera coverage, physical HDR, Photos
round trips/conflicts and current iPad/Mac runtime still need acceptance.

## Inherited foundation

Unveil already supplied the native shell, Metal canvas, Rust bridge, basic adjustments, import,
undo/redo, before/after, Files/Photos home and diagnostics. These were not newly created here.
The separate web wrapper and its private CloudKit sync remain outside this native app.
See [verification](Docs/Verification/), [engine changes](Engine/CHANGES.md) and [next steps](Docs/NEXT-STEPS.md).
