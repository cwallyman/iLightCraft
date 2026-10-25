# U2.1 Tone Curves — 2026-10-20

Implementation and delivery are complete for a first native point-curve editor. Acceptance remains pending.

## Behavior

- Mac/iPad toolbar icon with hover label; iPhone More > Tone Curves.
- RGB/master plus red, green and blue curves; 64-point bound and finite normalized coordinates.
- Tap to insert/select; drag points; release commits one undoable engine `develop.curve` edit.
- Point selector and Input/Output sliders provide precise and accessible editing. Input anchors at
  0 and 1 stay fixed horizontally; their output can move. Interior points can be deleted.
- Reset Channel or Reset All Channels (`curve.reset` point curves) preserves unrelated settings.
- Graph uses the renderer's Fritsch–Carlson interpolation. Photo preview refreshes on release,
  not continuously during a drag. It is an SDR sRGB PNG, maximum long edge 1200; the main editor
  and final output retain their existing HDR/output processing.
- Curve changes use the normal model edit queue. The native advanced-settings undo snapshot now
  includes the whole curve object, including parametric values. Saved catalog/Photos settings already
  include the curve. Back follows the existing Photos auto-save behavior.
- Invalid saved curves report an error; Reset All Channels is available for recovery. Failed commands
  reread saved settings when possible. Preview failures retain committed edits and offer undo.

## Evidence

- Final Debug Mac Catalyst and universal iOS builds passed. No Rust bridge change/rebuild required:
  existing shared commands/rendering/serialization implement curves.
- Mac app signed, signature verified, installed at /Applications/iLightCraft.app and launched with
  the procedural gradient fixture. Read-only accessibility inspection confirmed the four channels,
  graph, point controls, resets and Undo/Redo. The first screenshot exposed a tall graph; corrected
  aspect/frame ordering and preview height. Final screenshot showed a square graph with aligned
  endpoints/channel controls. The sheet scrolls to its precise/reset controls.
- iPad app persistent Application Support backed up, signed bundle verified and installed on paired
  iPad Air 11-inch (M3). Launch result is recorded separately below.
- Added `iLightCraftTests/ToneCurveTests.swift`: invalid/overlapping input, neighbor/endpoint bounds,
  interpolation knots/monotonicity, and inclusion of all channels/parametric values in undo settings.
  Tests are saved and not run or compiled by the app-only builds, per user preference. No full suite,
  benchmark, photo export comparison, Photos write or physical drag check performed.
- No upstream CI or commit performed; unrelated existing local changes preserved.

## Saved hands-on checks

1. Open a disposable photo, tap/drag RGB points and check the image changes after release. Repeat for
   each color channel; verify switching channels retains their points.
2. Use point selector, Input/Output sliders, Add/Delete. Check black/white input anchors and neighbor
   ordering. Try dragging off the graph and using Pencil/mouse/touch.
3. Undo/redo each edit and reset; verify unrelated crop, masks and sliders are retained.
4. Close/reopen and relaunch. Compare JPEG/TIFF export with the editor and test RAW/HDR output.
5. Open from Photos, change the curve, press Back and reopen; inspect settings, render and original.
6. Check iPhone portrait/landscape and iPad/Mac narrow windows, scrolling and accessibility.

- iPad automatic launch was blocked by its lock screen; installation succeeded. Unlock and open iLightCraft for physical checks.

## Right dock update

Mac/iPad now open this tool in the right-hand editor dock, without a duplicate photo preview.
iPhone retains the sheet. See [right-tool-dock.md](right-tool-dock.md) for delivery and layout evidence.

## Smaller graph for scrolling — 2026-10-20

Reduced the square graph maximum from 320 to 260 points and added 16-point horizontal
scroll margins. In narrower docks those margins also reduce the graph size, leaving room
to scroll beside it without touching its point-edit gesture. Curve math and precise controls
are unchanged. App builds/install outcomes recorded after delivery; no launches or automated
suites/benchmarks by the user's standing request.

Mac Catalyst and universal iOS builds passed (`curve-size-mac.log`, `curve-size-ios.log`).
Signed Mac update installed and signature verified; signed iPad update installed successfully.
No visual/physical check or new tests for this layout-only sizing change. iPhone first install
hit a CoreDevice remote connection error; retry result recorded below.
The iPhone retry succeeded. This graph-size update is installed on iPhone, iPad and Mac;
none were launched, per the standing request.
