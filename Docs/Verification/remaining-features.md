# Remaining native features — 2026-10-20

Scope: missing-feature queue items 1–7 and portable backup/restore from item 10.
Items 8 and 9 are skipped by user instruction. User selected backup/restore first, CloudKit later.

## Implemented behavior

- Point Color sampling on the main photo, eight samples, hue/saturation/luminance and range controls.
- Shadows/midtones/highlights/global color wheels with blending and balance.
- Embedded lens data detection and correction toggle, manual optics/CA/defringe and geometry controls, Upright and 2–4 main-photo perspective guides.
- Brush, linear/radial, color/luminance manual selections with add/subtract/intersect; main-photo coverage; local tone and detail controls alongside mask color.
- Remove/Heal/Clone, brush size/feather/opacity, explicit source or automatic source, saved repair updates/deletion.
- Native presets: save, favorite, apply, `.lcpreset` import/export. Selective copy/paste; up to 20 other imported photos per batch, explicit panel-local undo/redo and persistent per-photo history.
- Named versions, alternate local copies, persistent history restore and reference comparison beside the main photo.
- Settings: portable checksummed library backup, including imported source media. Recovery validates checksums, copies into a new app-owned library, rebases source paths and stages activation for the next launch. If the engine cannot open it, startup falls back to the previous library. The original library remains retained; device-specific Photos links are excluded.

## Evidence and limits

Final engine/app build and install logs are kept locally in `LocalVerification/mac-install/remaining-features-*`.
This update does not launch apps, run suites or take runtime screenshots, following user instructions.
Saved regression coverage is in `RemainingFeaturesTests.swift`, existing color/mask tests and engine `tests_color.rs`; tests are unrun and are not evidence of behavior passing.

Physical acceptance remains for every new workflow: rendering fidelity, persistence/export, undo/redo, main-photo coordinates after crop/perspective/orientation, iPhone portrait/landscape and control placement, Photos save-on-Back, large-file memory and backup/recovery round trips. Use disposable media and a disposable library for recovery checks.

External lens-profile selection/catalog, pressure-sensitive Pencil brush refinement, private CloudKit sync/signing and conflict recovery are not implemented. Portable backup supports the current native catalog layout, with manifest version 1; arbitrary historical migration is not claimed. External custom LUT/profile dependencies outside the library are not explicitly packaged. Spatial tools use bounded SDR previews; full-resolution/HDR Metal canvas resumes on closing them. Batch settings affect local imported photos, not source Photos assets; panel batch undo expires when the panel closes. Version create/rename/delete are persistent catalog operations, separate from current-photo adjustment undo.

## Delivery record

- Engine XCFramework: release compilation and packaging passed for physical iOS, iOS simulator and Apple Silicon Mac Catalyst.
- Final Mac Catalyst app build: passed. Updated `/Applications/iLightCraft.app`; strict deep signature verification passed.
- Final iOS app build: passed; development signature verification passed.
- iPad Air 11-inch M3: `devicectl` reported **App installed**, bundle `com.cwallyman.iLightCraft`.
- iPhone 17 Pro: `devicectl` reported **App installed**, same bundle.
- These were in-place updates; no app containers were deleted. Existing earlier backup artifacts retained; no new device-library backup was verified during this install.
- Apps were not launched. No functional, visual, full test-suite or benchmark pass is claimed.
