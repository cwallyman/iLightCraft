# Toolbar, semantic masks and Photos save-on-back — 2026-10-20

Implemented:
- Hover label overlay plus native help on editor toolbar controls (mouse/trackpad/hover input).
- Direct Masks, Remove, Library Analysis, Merge, Lens Blur and AI Enhancement buttons on
  Mac/iPad; named entries in the iPhone More menu, each opening the matching section.
- Sky mask, independent person silhouettes, and independent combined face/body skin masks.
  Models are bundled and local. See ../Models/README.md for sources, contracts and limits.
- Photos-backed Back waits for pending edits, compares complete settings against the opened/
  last-saved snapshot, and saves the same asset before leaving. Failure/conflict keeps the editor
  visible and retains the draft. File-backed edits do not trigger Photos writes. Repeated Back is
  blocked while checking/saving. The UI is disabled during that operation.

Delivery evidence:
- Final Mac Catalyst and universal iOS Debug builds passed.
- Both bundles contain compiled SkySegSmall and SkinSeg resources and license/notice files.
- Mac app signature verified, installed at /Applications/iLightCraft.app, launched; process confirmed.
- iPad Application Support, Preferences and Documents backed up before installation. The initial
  whole-Library copy could not read an OS-owned SplashBoard snapshot; the persistent directories
  were then copied successfully on their own.
- Signed iPad app verified and installed successfully on the paired iPad Air 11-inch (M3).
- iPad launch was blocked by the device lock. Unlock and open iLightCraft to exercise the update.
- No full automated suites, benchmark, real-photo mask assessment or Photos save round-trip run.
  User requested builds and installations. No upstream CI or commit performed.

Saved hands-on checks:
- Hover each icon; check direct section destinations and narrow iPad toolbar layout.
- Select sky with/without sky; use a group portrait and select each person's independent mask.
- Check skin masks for varied skin tones, clothes, occlusion and small people. Apply exposure,
  change selected mask, undo/redo, export and reopen. Coverage overlays for newly created masks
  remain available while the tools sheet stays open; prior-session overlays are not reconstructed.
- From Photos: change a slider/mask/crop, press Back, reopen and inspect settings/output/original.
- No-op Back should avoid a new Photos save. Undo to the opened settings should also be a no-op.
- Denied Photos access, external edit conflicts and render/write failure must keep the editor open.

## Hover follow-up — 2026-10-20

User reported the SwiftUI help/onHover labels did not work. Toolbar controls now use
a custom UIHostingController-backed toolbar view with UIToolTipInteraction and a
UIHoverGestureRecognizer attached to its actual UIView. Hover updates the editor label;
the native interaction provides dwell tooltips. Disabled/color-scheme state is forwarded
to hosted controls. iPhone menu items keep their normal SwiftUI representation. Undo/redo
shortcuts stay attached to the hosted buttons.

Mac and iOS builds passed. Signed updates installed on Mac and iPad; Mac process confirmed.
iPad Application Support backed up before replacement. Physical mouse/Pencil hover has not
been independently verified; no synthetic OS input or full test suite was run.

## Hover positioning and Back alignment — 2026-10-20

The user supplied screenshots showing the Back glyph below its button and labels away from
the hovered control. The hosted toolbar views now disable inherited safe areas and request
intrinsic sizing. The global centered overlay is removed. Each native hover coordinator
positions a noninteractive label bubble six points below its own control's window-space
bounds, centered on that control and constrained at window edges. The bubble is removed on
hover exit/cancellation and representable teardown. Native duplicate tooltips are removed.

Both builds passed. Mac installed and launched with a procedural gradient fixture; read-only
app screenshot confirmed Back inside its button and aligned toolbar glyphs. Actual pointer
hover positioning still needs hands-on confirmation. iPad persistent library backed up, then
the signed app installed. No full test suite or OS synthetic input used.
