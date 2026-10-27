# Crop Geometry expander

Geometry now expands/collapses inline in Crop using the same disclosure styling
as Edit. It shares Crop's scrolling column, theme and yellow changed indicators.
Opening/collapsing the section makes no saved edit and does not replace Crop.

Upright, guides, Constrain Crop and geometry sliders retain their existing engine
actions. Actual geometry actions first save a changed crop draft, keeping guide
coordinates aligned with its orientation. The crop preview reloads after those
actions. Guided interaction uses the existing main-photo viewport; collapsing
Geometry cancels unfinished guides. Busy operations block dismissal/Done and
crop changes during guide drawing. The UI notes that geometry edits apply
immediately, matching their existing behavior.

Device build/sign/install logs: LocalVerification/crop-geometry-expander-*.
No simulator or automated tests run. Manual acceptance: expand/collapse Geometry,
adjust/reset a slider, use Upright or guided lines, return to the crop handles,
and finish with Done. Visual and interaction acceptance remains with the user.

Delivery: device build and strict signature verification passed; `devicectl`
confirmed the iPad installation, sequence 2708. The app was not launched.
