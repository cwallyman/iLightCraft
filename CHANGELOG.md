# iLightCraft change history

Changes through 2026-10-25, relative to the upstream native baseline `79be4e4`. First published implementation:
[`2f71fe9`](https://github.com/cwallyman/iLightCraft/commit/2f71fe9ad954352cdf0eec2ab64f765f56c0f3bc).
Implementation, delivery and acceptance are recorded separately.

## 0.11.0 release and Xcode Cloud (2026-10-25)

- Signed iOS and Mac Catalyst archives uploaded successfully to App Store Connect; processing and TestFlight availability remain unverified.
- Configured automatic Cloud builds for iOS and Apple Silicon Mac Catalyst; both passed at `303faf0`. Archive/TestFlight post-actions remain pending.
- Added isolated Rust/model bootstrap, verified download retries and portable branding checks.
- Removed three Swift compiler warnings. One nonblocking Mac Cloud Metal toolchain search-path warning remains.
- Kept the current engine for 0.11.0; upstream engine updates are deferred to the next version.

## iLightCraft identity and release preparation (2026-10-21)

- Renamed native source/test folders, Xcode project/targets/schemes, executable, Swift bridge module, Rust FFI package, internal commands, launch flags and scripts to iLightCraft.
- New Photos envelopes use the iLightCraft identifier; a read-only compatibility adapter retains access to old saved edits and migrates the library-source preference. Upstream copyright/license notices and baseline evidence remain intact.
- Release uses the current developer team and a clean app identity. Local Debug identity is isolated in an ignored configuration for existing test-container updates.
- Added a privacy manifest and bundled license/credit viewer; corrected Photos permission wording for save-on-Back. Removed the unsupported increased-memory entitlement; Mac Release enables hardened runtime. Disk-space launch diagnostics are compiled out of Release.
- See [App Store readiness](Docs/APP-STORE-READINESS.md) for archive evidence and remaining submission requirements.

## Remaining native tools and portable recovery (2026-10-20)

- Added Point Color, grading, optics/perspective, manual mask shapes/ranges/brush and mask tone/detail controls.
- Added repair source/mode/refinement, presets/selective batch edits, named versions/history and reference comparison.
- Added checksum-verified portable backup and separate-library staged restore in Settings. CloudKit deferred by user; queue items 8 and 9 skipped.
- Build/install evidence and implementation limits: [remaining features](Docs/Verification/remaining-features.md). Tests are saved, unrun by request; physical acceptance remains.

## Color adjustments inside masks (2026-10-20)

- Added per-mask Temperature, Tint, Hue, Saturation, Colorize hue/Amount and quick color swatches alongside Exposure.
- Skin masks can be corrected independently; separate Subject/Background masks can use red/blue or other colors.
- Applies through engine mask settings, hides the coverage highlight to reveal the result and retains undo/persistence/export behavior.
- See [behavior, limits and saved checks](Docs/Verification/mask-color.md).

## Smaller Tone Curves graph (2026-10-20)

- Reduced the graph maximum to 260 points and added side margins, making the panel easier to scroll without dragging curve points.
- See [Tone Curves verification](Docs/Verification/tone-curves.md).

## Main-photo masks, removal and crop (2026-10-20)

- Moved mask coverage/object picks, removal strokes and crop/rotate interaction onto the main photo; panels now contain their controls without duplicate photos.
- Shared observable sessions keep tool controls and main-photo interaction aligned; added pinch/two-finger pan with normalized coordinates and undo preview refresh.
- Reordered the core tools to Edit, Crop & Rotate, Remove, Masks, then standalone color and extra tools.
- Spatial modes reuse the existing bounded SDR uncropped preview; full-resolution/HDR main canvas resumes after closing the tool. See [behavior, limits and delivery](Docs/Verification/main-photo-tools.md).

## Adaptive controls and placement setting (2026-10-20)

- iPhone tools now stay in a scrollable lower-half dock in portrait and a side dock in landscape, leaving the main photo available for pinch/pan inspection.
- Added More > Settings > Controls side (Left/Right), saved per device and applied to all side panels on iPhone/iPad/Mac.
- Retained tool/canvas identity across layout changes and existing busy-operation protection.
- See [behavior and delivery evidence](Docs/Verification/adaptive-controls.md). Apps are installed without launching, per request.

## More menu correction (2026-10-20)

- Kept More as a native menu outside a bounded scrolling tool strip on Mac/iPad, avoiding empty system overflow popovers for custom hover buttons.
- Preserved tool hover/selection and iPhone More entries; added always-available Info and Fit Photo menu actions.
- See [toolbar evidence and manual checks](Docs/Verification/editor-toolbar.md).

## Active toolbar tool highlight (2026-10-20)

- Added explicit selected icon color, rounded background/outline and accessibility state for the open editor tool.
- Highlight follows panel selection and clears on closing or switching tools; HDR and Show Original show their enabled states.
- Mac/iOS builds passed and Mac appearance inspected; see [verification](Docs/Verification/right-tool-dock.md).

## HSL Mixer and Profiles: U2.2 partial (2026-10-20)

- Added eight HSL color bands with Hue, Saturation and Luminance, live draft rendering, band/all resets and undo/redo.
- Added 22 original built-in profiles grouped by style, Amount (0–200%), search, favorites, recent choices and reset to Color. Amount applies on release.
- Included the complete profile object in native undo snapshots; HSL uses the existing adjustment queue and saved settings.
- Mac/iPad use separate toolbar icons and the right dock; iPhone uses More and sheets.
- Mac Catalyst and universal iOS builds passed; Mac dock visually inspected. See [delivery and saved acceptance checks](Docs/Verification/hsl-profiles.md).

## Right-side editor tool panels (2026-10-20)

- Moved Tone Curves, Masks, Remove, Library Analysis, Merge, Lens Blur, AI Enhancement,
  Crop & Rotate, Export and Info into the right-hand dock on Mac/iPad.
- Kept one tool beside the existing canvas, local panel actions, active-tool tint, and operation
  guards for switching/Back. Edit and other panels replace each other; iPhone keeps sheets.
- Removed the duplicate Tone Curves preview in the dock. Interactive crop/mask/remove previews
  remain inside their panels. Corrected mask choice wrapping for narrow panel widths.
- See [layout and verification](Docs/Verification/right-tool-dock.md).

## Tone Curves: U2.1 (2026-10-20)

- Added direct Mac/iPad toolbar access and an iPhone More entry, with a native curve sheet.
- Added RGB/red/green/blue channels, normalized point addition/dragging/deletion, precise Input/Output
  sliders, reset-current/reset-all-point-channels and in-sheet Undo/Redo. Each released drag is one edit.
- Draws the same Fritsch–Carlson interpolation as the Rust renderer and refreshes a cropped, color-managed
  SDR photo preview through the shared export pipeline after each committed edit.
- Included the complete curve object in native undo snapshots. Existing catalog/Photos settings and
  final export paths retain curves; original photo files are unchanged.
- Mac and universal iOS builds passed; installed on Mac and iPad. Corrected square graph sizing after
  the Mac visual review. Saved tests remain unrun by user preference; persistence/output/Photos
  round trips and physical curve interactions remain acceptance checks.
- See [Tone Curves verification](Docs/Verification/tone-curves.md).

## Priority 4 on-device tools: U4.1–U4.6 (partial, 2026-10-20)

- Added More > On-device Tools with Masks, Remove, Library Analysis, Merge, Lens Blur and AI Enhancement.
- Added Vision subject/background/people/foreground-instance selections as bounded normalized engine masks;
  exposure, combinations, inversion, deletion and edge refinement. Undo captures advanced saved settings.
- Added brush-based content-aware patch healing using the existing full-resolution engine spot renderer.
- Added local labels/OCR/face counts, a bounded private imported-photo index, cancellable indexing, keyword
  and optional English label/OCR-vector search, opening saved drafts and clearing the index.
- Added ordered-source HDR/panorama/HDR-panorama background jobs, deghost/projection/crop options,
  estimated-memory rejection, cancellation on background, unique new DNGs and direct catalog opening.
- Added user-triggered pinned/checksummed model installation with retained licenses and removal controls:
  Depth Anything V2 Small F16 (Apache-2.0), Real-ESRGAN x4v3 variants (BSD-3-Clause).
- Added local relative-depth focus/range/blur into a separate float TIFF. Added padded-tile RGB AI denoise
  and 2× enhancement into separate opaque SDR PNGs; explicitly reject HDR mode instead of silently converting.
- Kept derived copies and opened local drafts detached from prior Photos assets, preventing unrelated saves.
- Saved Rust and Swift regression checks; no automated suites, benchmarks or model inference run by the agent.
- Corrected roadmap numbering to include HEIC as item 1, making Priority 4 items 18–23. Hosted sharing stays item 24.
- Full scope is not complete: sky/body-part/depth selections, adaptive presets, sensor RAW denoise/Raw Details,
  editable blur/bokeh/refinement, generative/reflection/automatic distraction removal, identity recognition and
  joint image-text search remain. Real model/merge/output/device acceptance is pending.
- See [bounded evidence and acceptance](Docs/Verification/priority4-on-device.md) and [model provenance](Docs/Models/README.md).

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

- Published the native app as cwallyman/iLightCraft, preserving the iLightCraft fork history/upstream remote.
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

iLightCraft already supplied the native shell, Metal canvas, Rust bridge, basic adjustments, import,
undo/redo, before/after, Files/Photos home and diagnostics. These were not newly created here.
The separate web wrapper and its private CloudKit sync remain outside this native app.
See [verification](Docs/Verification/), [engine changes](Engine/CHANGES.md) and [next steps](Docs/NEXT-STEPS.md).
