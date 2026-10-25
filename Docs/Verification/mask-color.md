# Mask color adjustments — 2026-10-20

## Behavior

Every saved mask now exposes Exposure, Temperature, Tint, Hue shift and Saturation, plus
Colorize target hue (0–360°), Amount (0–100%) and eight quick swatches. Natural skin correction
uses the balance/hue/saturation controls on a skin mask. Colorize swatches set local Saturation
to -100 and add the chosen hue at full Amount through the existing engine color overlay.
This keeps lighting/shading rather than painting a flat opaque color. Overlapping/feathered
coverage and global color edits can blend colors at edges or affect the exact resulting hue.

Swatches apply immediately; sliders apply on release, with an explicit Apply button for
accessibility/fallback. New selections show their coverage; applying an adjustment hides the
coverage highlight to reveal the real edited photo. It can be enabled again with Show selection
overlay. Reset Mask Color restores the exposed color controls to neutral while retaining exposure.

Each mask has independent values. Create a Subject mask, choose Red; create a separate
Background mask, choose Blue. Select saved person/skin masks to correct each person's tone
independently. These operations do not recolor the selection highlight alone: color parameters
are sent to engine `mask.adjust`, rendered into the main working preview and retained by export.

The request snapshots the selected ID/values and deep-merges only seven exposed local fields,
preserving other engine mask settings. Restoring a saved mask restores all exposed values;
legacy exposure-only native fixtures decode with neutral color defaults. Invalid/non-finite
values produce an error rather than reaching sliders/commands. Stale mask IDs after undo are
replaced with a remaining selection or cleared. Native advanced undo already includes full masks;
no engine changes, new model, original-file replacement or bridge rebuild required.

## Evidence and limits

- Mac Catalyst and universal iOS app builds passed for the controls. Final delivery results below.
- Added saved tests in `iLightCraftTests/MaskColorAdjustmentsTests.swift`: legacy decoding, command
  keys, independent red/blue settings, reset retaining exposure, invalid input and real bridge
  two-mask persistence/undo/redo using generated half-image coverage. These are unrun and not
  compiled by app-only builds. No automated suites/benchmarks or model inference run.
- No app launch, screenshots, real photo comparison, Photos save or output inspection by request.
  Existing main spatial viewport remains an uncropped SDR preview bounded to 1600 × 1600;
  final output still uses normalized settings at its requested resolution.

## Saved acceptance checks

1. On disposable colorful media, create separate Subject/Background masks, use Red/Blue, and
   confirm the actual image changes after the selection overlay hides. Compare edge feathering.
2. Create separate skin masks; adjust Temperature/Tint/Hue/Saturation and verify other people
   remain unchanged. Check weak/overlapping selections and partial coverage.
3. Switch among saved masks, alter Amount/target hue, undo/redo and reset color. Check exposure
   and unrelated crop, contrast, global HSL/profile and other masks remain intact.
4. Close/reopen/relaunch; export JPEG/TIFF and check alignment, color and saved values. Test
   Photos save-on-Back/reopen with a disposable asset; preserve the original.
5. Check portrait/landscape, both control sides, scrolling, pointer/Pencil/touch and VoiceOver.

Final delivery:

- Final Mac Catalyst and universal iOS Debug builds passed (`mask-color-mac.log` and
  `mask-color-ios.log` in repository-root LocalVerification/mac-install).
- Signed Mac app installed at `/Applications/iLightCraft.app`; strict signature verification
  passed. Signed universal bundle installed successfully on paired iPhone 17 Pro and iPad Air
  11-inch (M3), confirmed by devicectl install results. No apps launched.
