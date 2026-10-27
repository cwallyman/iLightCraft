# iLightCraft change history

Changes through 2026-10-27, relative to the upstream native baseline `79be4e4`. First published implementation:
[`2f71fe9`](https://github.com/cwallyman/iLightCraft/commit/2f71fe9ad954352cdf0eec2ab64f765f56c0f3bc).
Implementation, delivery and acceptance are recorded separately.

## Top-left Back button (2026-10-27)

- Restored Back to the top-left on iPhone and iPad, enlarged its icon to 26 points with a 44-point tap target, and removed its iPhone More-menu entry.

## Top-bar Undo and Redo (2026-10-27)

- Moved Undo and Redo from More into the top bar immediately beside More on iPhone and iPad, with 44-point touch targets and existing keyboard shortcuts and availability rules.

## Photo comparison and phone toolbar (2026-10-27)

- Replaced the five bottom view buttons with Single Photo and side-by-side Before / Edited for the same photo.
- Comparison renders bounded previews from the engine's before state and current edits, retaining current crop/orientation; refreshes on committed edits and panel changes. Spatial editing returns to Single Photo.
- iPhone top actions, including Back, Zoom and Export, are in More. Increased the More icon to 26 points on iPhone and iPad, with a 48-point touch target.
- Physical-device build/install evidence is recorded in Docs/Verification/2026-10-27-before-edited-phone-menu.md. No simulators or automated tests run.

## Settings and preset menu cleanup (2026-10-26)

- Removed diagnostic tools from the editor's main More menu, including Debug builds.
- Removed Presets & Batch Editing from the editor's main More menu; Batch Editing is in the Presets panel's options.
- Removed static explanatory paragraphs from Settings, keeping its controls and operational status/errors.

## Ten-key numeric entry (2026-10-26)

- Editable numeric readouts open a themed ten-key popup with decimal/sign keys as needed and bounded, single-commit entry.
- Covered adjustment tools, masks/repair, crop/Geometry, curves, preset/profile Amount, export sizes and zoom. Cancel/outside dismissal does not apply an edit.
- Retained yellow changed-state styling and existing undo paths. No simulator or automated tests run.

## Active mask highlight and bottom divider (2026-10-26)

- Active mask rows use the preset yellow for their name/icon and a subtle yellow background.
- Removed the divider overlay that appeared vertically through the bottom rating stars.

## Toolbar alignment and status banner (2026-10-26)

- Right-aligned the Presets-through-Info toolbar group next to More, retaining scrolling on narrow layouts.
- Removed the bottom Photos status banner that covered photo controls. Saving progress and error handling remain.

## Crop Geometry expander (2026-10-26)

- Geometry expands inline in Crop like Edit's submenus, retaining themed controls and changed-value highlights.
- Kept Upright/guides connected to the main photo and refreshed the crop preview after geometry edits. No simulator or automated tests run.

## Project version cleanup (2026-10-26)

- Moved AppleWrapper, obsolete Unveil products, old DerivedData copies, engine framework snapshots and superseded archives to recoverable Trash.
- Preserved the current NativeReference source/app, submitted 0.11.0 iOS/Mac archives, device backups and Rust reference source. One active Xcode app project remains.
- Recorded a restore manifest and verified project listing/current app signature; no simulator or test run.

## Yellow changed-control indicators (2026-10-26)

- Changed adjustment labels, values and slider handles use the selected preset's yellow; unchanged controls retain neutral styling.
- Compared with actual photo/control defaults, including RAW/as-shot and nonzero brush/profile/repair settings. Resetting to a default clears its highlight.
- Applied shared indicators across editor tools while retaining existing gradients, gestures and editing behavior. No simulators or automated tests run.

## Preset selection replacement (2026-10-26)

- Selecting a different preset now replaces the active preset from its original baseline instead of accumulating both presets' settings.
- Earlier edits remain; Amount and Reset share that baseline. Active selection survives closing/reopening Presets for the open photo, with guards against discarding intervening edits.
- Saved replacement/reopening regression coverage. No simulator or automated tests run.

## Masking icon tiles and Content-Aware (2026-10-26)

- Matched the Masking panel's icon-tile layout and mask/overlay controls, including Each Person and Each Person's Skin.
- Enabled real Content-Aware patch completion in Masking and Remove through a focused pure-Rust engine backport; saved fills remain non-destructive.
- Added actual mask pins, preview overlay colors/modes/opacity and component actions. Person and skin selection retain the existing local implementation.
- Physical iOS and Mac Catalyst engine builds and iOS app build passed. No simulator, automated tests or performance benchmarks run; manual acceptance remains with the user.

## Shared menu theme and capture row (2026-10-26)

- Applied Edit's theme across editor menus and sheets, replacing native Form/List row backgrounds with shared flat sections and dividers.
- Restored the always-visible ISO, focal length, aperture and shutter row beneath the histogram; missing values show a dash.
- Missing catalog capture fields fall back to read-only metadata from retained originals for Apple-decoded editing copies. Saved regression coverage; no simulators or automated tests run.

## Inline Edit menus and themed sliders (2026-10-26)

- Edit's child menus now expand inline, including Profile, Curve, Color Mixer, Point Color, Color Grading and Defringe. White Balance sampling keeps Edit visible.
- Removed AI Denoise from Edit. Unified editor slider tracks, hollow handles, gradients and text/accent colors with LightCraft's Charcoal theme; retained precision adjustment behavior.
- Added Curve channel rings and the engine-backed Point Curve preset menu with Save/Import/Export and Reset. Temp/Tint use the desktop's relative display scales.
- No simulator or automated tests were run. Hands-on acceptance remains with the user.

## Menu scrolling space (2026-10-26)

- Added a shared 32-point blank area at the right of editor menu content for scrolling beside controls, including the Profile popover.
- Separated the Edit section eye buttons from their expand arrows with a 20-point gap and gave each eye button a 44-point touch target.
- Applied the same margin to standalone editor tools. No simulator or automated tests were run.

## Profile popover from Edit (2026-10-26)

- Edit's Profile button opens the grouped chooser as an anchored popover, keeping Edit underneath.
- Tapping outside returns to Edit and refreshes the selected profile label and controls.
- No simulator or automated tests were run; manual acceptance remains with the user.

## Desktop menu alignment (2026-10-26)

- Matched the shared panel colors, headers, section order and nested control grouping to LightCraft's desktop source.
- Added white-balance selection, section visibility/reset/solo actions, vignette styles, B&W mixer, dust actions and local mask Moiré/Defringe controls; separated Geometry from Optics.
- Consolidated Info metadata saving and kept native-only tools under More. Content-Aware and sensor AI Denoise remain unavailable in the retained engine.
- Device build passed. No simulator or automated tests were run; hands-on acceptance remains with the user.

## Selected preset Amount and Reset (2026-10-26)

- Selecting a preset reveals the Amount strip below the header, starting at 100, with a 0–200 range.
- Amount changes use the settings before that selection; Presets > More > Reset restores those earlier edits and clears selection. Stale operations refuse to overwrite intervening edits.
- Regression coverage is saved for manual execution. No simulator or automated test run was performed.

## Grouped LightCraft presets (2026-10-26)

- Replaced the default presets form with collapsible alphabetical groups, indented preset rows and the desktop-style More/+ header.
- Exposes all 41 LightCraft built-ins across ten groups, preserving their exact existing engine settings and in-group order, plus user presets and favorites.
- Moved creation fields to + and preset management/import/export/filter options to menus. Device build passed; hands-on testing is left to the user, with no simulator run.

## LightCraft toolbar and photo controls (2026-10-26)

- Ordered the top tools as requested, with separate Versions and History and dividers matching the desktop rail. Native extras are in More.
- Added the bottom photo strip with grid/detail/compare/survey, sort, ratings/flags and settings copy/paste/options.
- Expanded the shared Edit, Red Eye, Keywords, Info, Versions/History and Crop workflows; retained the native precision sliders and engine.
- Added synthetic command/geometry checks and updated the UI test engine for the new read-only queries. Final targeted test run and device build passed before the user stopped simulator testing.
- Further simulator/automated testing is deferred to the user by request.

## Native icon consistency (2026-10-26)

- Replaced app-owned SF Symbols throughout the toolbar, tool panels, menus, Photos browser, navigation and diagnostics with LightCraft's original vector icon catalog.
- Preserved scalable template paths, tint, selected/disabled states, text labels, accessibility identifiers and keyboard shortcuts.
- Added a reproducible export tool, pinned desktop icon source, licenses and catalog/reference checks. Native-only tools use documented semantic equivalents from the desktop catalog; system-owned pickers/share sheets keep Apple's UI.
- Existing iLightCraft app/home lynx branding remains unchanged.

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
