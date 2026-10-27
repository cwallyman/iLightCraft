# Inline Edit menus and themed sliders

Updated 2026-10-26 from the user's three screenshots and desktop LightCraft
`panels/edit.rs`, `widgets.rs` and the retained engine's control specifications.
This supersedes the earlier Profile popover behavior: Profile now expands inline.

- Profile, Curve, Color Mixer/B&W Mixer, Point Color, Color Grading and Defringe
  expand inside Edit's scrolling column. Embedded tools omit their standalone
  title and scroll container, preserving the surrounding Edit sections.
- White Balance Selector samples the main photo while Edit stays visible.
  Inline Point Color retains main-photo sampling. Top-level toolbar tools still
  use their normal reserved panel.
- AI Denoise was removed from Edit.
- All native editor slider tracks use the shared thin line and hollow gray
  handle. Temperature, Tint, Vibrance/Saturation, mixer, Defringe, calibration
  and curve refinement use LightCraft-derived color gradients. Text and control
  accents use the existing Charcoal panel tokens. Core adjustment sliders keep
  their precision gestures, direct value entry, undo and accessibility actions.
- Edit's Temp and Tint display the desktop's relative -100 to 100 scales; Temp
  converts to/from Kelvin through the same reciprocal-temperature mapping.
- Curve includes RGB/master channel rings, the editable graph, a Point Curve
  preset menu, Save/Import/Export, Reset and expandable point details. Parametric
  Highlights/Lights/Darks/Shadows and Refine Saturation remain under the graph.
  Presets come from `curve.presets`, not duplicated native definitions. Embedded
  Curve avoids exporting a redundant second photo preview.
- The right scrolling margin and eye/expander separation remain. Purple/Green
  hue bounds are disabled when their corresponding Defringe amount is zero.

Verification is a device build and strict signing/install check, with evidence
under `LocalVerification/inline-edit-*`. No simulator or automated tests were
run, as requested. Physical visual and interaction acceptance remains with the
user: expand every child, scroll from the right gutter, adjust/reset sliders,
sample WB/Point Color on the photo, edit a Curve channel and apply/reset a curve
preset. Curve import is security-scoped and limited to files under 2 MB.

Delivery: the final Debug iOS device build, whitespace check and strict signature
verification passed. `devicectl` confirmed an in-place installation on the
physical iPad under the existing development identity, sequence 2652. The app
was not uninstalled or launched. No simulator or automated tests were run.
