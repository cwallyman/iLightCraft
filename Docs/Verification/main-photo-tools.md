# Main-photo spatial editing and tool order — 2026-10-20

## Behavior

- Masks, Remove and Crop & Rotate share their edit sessions with a zoomable main-photo
  viewport. Their dock contains controls only; no second crop/mask/removal photo is displayed.
- Mask coverage overlays and object taps use the main image. Removal strokes, including
  single-tap spots, are drawn there and applied with Remove Area. Brush size stays relative to
  image dimensions and stroke count remains capped at 2,048 points.
- Crop corners, thirds grid, outside dimming and position dragging are on the main image.
  Rotation, flips, aspect and straightening update that view. Cancel discards the local draft;
  Done uses the existing single undoable crop operation.
- Pinch zoom (1–8 times fit), two-finger pan and mouse drawing operate on one shared image/overlay
  transform. Input locations are converted into image-content coordinates before normalization,
  keeping zoom/pan independent from saved settings. A pinch that cancels drawing restores the
  unfinished gesture instead of saving an accidental stroke/crop change. Viewport resizing
  retains zoom and the image center where possible; orientation changes refit changed dimensions.
- Existing controls placement remains: iPhone portrait lower half, landscape side; per-device
  left/right setting. Main viewport and tool panel share the same observable session across
  rotation/side changes. Busy operations and active gestures guard against tool switching.
- Undo/redo refresh the spatial preview and mask controls. Reset All is disabled while a crop
  draft is open, and Show Original is disabled in these uncropped spatial tool modes. Normal
  Metal canvas editing/comparison remains available after closing the tool.

## Preview limits

Spatial tools deliberately show the uncropped, oriented working photo so alpha/stroke/crop
coordinates align with the existing engine operations. They reuse `ilightcraft.cropPreview`, currently
an SDR PNG bounded to 1600 × 1600; zoom magnifies that preview rather than requesting new
full-resolution tiles. The normal Metal canvas stays mounted underneath and resumes after the
tool closes, with its existing RAW/HDR and full-resolution zoom behavior. Final edits and exports
still use the engine's normalized full-image settings; no source photo is overwritten by this UI.
This is not a claim of new HDR spatial-preview or full-resolution loupe support.

## Tool order

The core order is **Edit → Crop & Rotate → Remove → Masks**, following the relative tool-strip
order in [Adobe's Develop module documentation](https://helpx.adobe.com/lightroom-classic/desktop/process-and-develop-photos/develop-module-tools.html#tools-in-the-tool-strip)
for the implemented tools (no Red Eye button is added). Remaining standalone shortcuts follow:
Profiles → Tone Curves → HSL Mixer → Lens Blur → AI Enhancement → Library Analysis → Merge →
HDR Editing → Show Original → Reset All, followed by Undo/Redo and Export. The iPhone More menu
uses the same tool ordering. Profiles/Curves/HSL remain standalone shortcuts by the user's prior
request; this is not a claim that every extra shortcut exists in Lightroom's toolbar.

Only published behavior/layout documentation was consulted. No Adobe app bundle, icons, profiles,
artwork or other assets were read or copied. New main-photo graphics are simple original paths,
recorded in assets/ATTRIBUTION.md.

## Evidence and saved checks

- Debug Mac Catalyst and universal iOS builds passed for the implementation. Final build/install
  results are recorded below. No app launch, screenshots or physical gestures exercised by request.
- Saved `iLightCraftTests/PhotoToolGeometryTests.swift` covers normalized location bounds, non-finite
  input, crop movement at edges, opposite anchors and aspect-preserving corner resizing.
  Tests are unrun and are not compiled by app-only builds. No suites/benchmarks run.
- Existing personal-library data and unrelated work preserved. No commit or upstream CI run.

Hands-on acceptance:

1. Check main photo only for each tool on all devices and every controls placement/orientation.
2. Pick an object and select sky/people/skin; toggle coverage, apply exposure and verify the
   result after closing. Repeat on images with prior crop/rotation/flips.
3. Draw/tap removal marks at fit and zoomed/panned views; compare result/export location and
   brush radius. Start a pinch while touching the image and check no accidental stroke is saved.
4. Drag each crop corner/interior, change aspect, straighten, rotate/flip, Cancel and Done.
   Repeat zoomed and after rotation/side changes; check undo/redo, export and Photos reopening.
5. Check narrow windows, safe areas, scroll reachability, pointer/Pencil/touch and accessibility.

Final delivery evidence:

- Final Mac Catalyst and universal iOS Debug builds succeeded (`main-photo-tools-mac.log`
  and `main-photo-tools-ios.log` under repository-root LocalVerification/mac-install).
- Mac bundle installed at `/Applications/iLightCraft.app`, development signed and strict
  signature verification passed. Signed universal app installed on iPhone 17 Pro.
- Fresh iPhone/iPad Application Support backup attempts timed out over CoreDevice. Earlier
  backups were retained; app updates do not request deletion of existing containers.
- No apps launched, in accordance with the user's instruction. Installation does not establish
  physical interaction, render alignment or Photos/output acceptance.
- iPad first install failed while CoreDevice mounted its developer image; a retry succeeded
  (`main-photo-tools-ipad-install-retry.log`). Final signed build is installed on all three
  target devices, with no launches requested or performed.
