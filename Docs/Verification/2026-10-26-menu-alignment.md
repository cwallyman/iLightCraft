# LightCraft menu alignment

Updated 2026-10-26. Compared the native editor with the desktop source in
`../crates/ui-egui/src/panels/` and its Charcoal theme, together with the user's
reference screenshots. This is a source/layout comparison; physical visual and
interaction acceptance remains with the user.

Later update: Content-Aware Fill was backported and enabled in Masking and
Remove. See [Masking and Content-Aware](2026-10-26-masking-content-aware.md).
The limitations below describe this earlier installation.

- Shared dock headers use a consistent height, typography, divider and Charcoal
  background/foreground colors. Native-only tools remain accessible from More.
- Edit follows Light, Color, Effects, Detail, Optics and Calibration, with section
  visibility, reset and solo actions. Added the white-balance picker/mode menu,
  B&W mixer, vignette styles and clearer nested curve, grain and detail controls.
- Geometry has its own panel, separate from Optics, linked from Crop. Optics
  distinguishes embedded lens corrections, manual corrections and Defringe.
- Remove exposes dust detection, spot count and deleting all spots. Masking adds
  local Moiré and Defringe controls and follows the shared adjustment ordering.
- Shared panels omit redundant native header buttons; Crop retains its draft
  Cancel/Done actions in a footer. Info uses one Save Metadata action with an
  explicit photo identity for metadata and label writes.

The retained engine has no Content-Aware spot mode or sensor AI Denoise. Those
desktop controls are shown disabled with an explanation; this change does not
upgrade the engine or claim complete behavioral parity with its newer version.

Verification: the final Debug iOS device build passed and `git diff --check`
passed. No simulator was started and no automated tests were run, as requested.
Build evidence: `LocalVerification/menu-alignment-ipad-final-build.log`.
Signing and physical-device installation evidence is recorded separately in
`LocalVerification/menu-alignment-sign.log` and
`LocalVerification/menu-alignment-ipad-install.log` / `.json`.

Delivery: strict code-sign verification passed. `devicectl` confirmed installation
on the physical iPad under the existing `com.cwallyman.UnveilNative` identity,
without uninstalling or launching the app. Device database sequence: 2620.
