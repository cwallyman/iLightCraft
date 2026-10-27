# LightCraft toolbar and photo panel

User scope, 2026-10-26: use LightCraft's side rail across the top; align shared panel
contents; put native extras in the three-dot menu; put the pictured bottom control
strip below the editor photo. The library browser is a separate surface.

## Layout and behavior

Top: Back, photo name, zoom percentage, Export, Presets, Edit, divider, Crop,
Remove, Masking, Red Eye, divider, Versions, History, Keywords, Info. The
three-dot menu follows the shared tools. Narrow widths scroll the tool groups;
Back/name/zoom/Export and More remain available. Undo/Redo retain keyboard
shortcuts and are in More. Shared icons use the original desktop vector catalog.

The bottom photo strip contains Photo Grid, Square Grid, Detail, Compare, Survey,
Sort, five rating stars, Unflagged/Pick/Reject, Copy/Paste Edit Settings and a
Copy Settings options gear. The circle is Unflagged, as in the desktop source.
Ratings, flags, sorting and settings use the retained engine's commands.

Grids render edited catalog previews, not original-file thumbnails. Compare
selects two photos; Survey supports up to eight at once. Imported catalog pages
load 50 at a time, with a 1,000-photo display limit and a 48 MB thumbnail cache.
Returning to a photo preserves the existing native Metal canvas. Switching away
from a Photos edit first requests its same-item save; a failure keeps it open.
Capture-date grouping is rendered in the grids. Date grouping for other sort
keys is not implemented in the native gallery yet.

## Shared panel content

- Edit: histogram, Auto/B&W/HDR/Reset, Profiles, Light/Tone Curve, Color/white
  balance/Color Mixer/Point Color/Color Grading, Effects/Vignette/Grain, full
  Detail sliders, Optics and Calibration. Core controls retain native precision
  sliders, draft updates and one edit per gesture. Additional controls come from
  `develop.controls`. Sensor-domain AI Denoise remains unavailable in the
  retained native build; the app's optional RGB model workflow stays in More.
- Crop: ratios, custom aspect, lock/swap, rotation/flips, straighten slider and
  numeric angle, line tool, composition overlays and Geometry entry. Crop remains
  a staged draft with Done/Cancel. Composition guides are original geometry.
- Remove and Masking: existing native repair/mask workflows and tone/color/detail
  controls; shared tools keep their own panels.
- Red Eye: photo selection, pupil/radius/darken, Pet Eye, saved corrections,
  catchlights and deletion.
- Versions: separate from History, Named/Auto tabs, create/restore/rename/update/
  set-before/delete; History has restore, set-before, create-version and clear.
- Keywords: photo keywords, containing components, retained-engine export view,
  suggestions, keyword sets and library keyword list. This panel targets the
  current photo. The newer desktop's synonym/export-policy editor and arbitrary
  multi-selection keywording are not implemented by the retained native engine.
- Info: camera/file/capture data, ratings/color label, descriptive metadata and
  copyright/location fields, plus all EXIF/XMP metadata. Desktop-specific file
  reveal, managed-import rename and capture-time editing are not exposed here.

More holds native Apple Photos save, optional local model workflows, local
analysis, merge, batch UI, backup/settings and diagnostics. System Files/share
sheets keep Apple's UI. Existing app identity and library data are retained.

## Validation

Results and delivery are recorded below after final checks. Initial real-engine
synthetic workflow passed. Initial UI tests identified obsolete fake-engine query
responses and a core-slider invalidation regression; both were repaired before
final verification. No user media is used for automated tests or visual captures.

The final targeted simulator test command completed successfully before the user
stopped simulator work. The device Debug build and icon catalog checks passed.
At the user's request, no further simulator runs, screenshots or automated tests
will be performed; hands-on testing is reserved for the user. The task-created
simulator was shut down. No physical app launch was requested.

Delivery: `devicectl` confirmed **App installed** on the paired iPad Air 11-inch
(M3), using its existing `com.cwallyman.UnveilNative` identity. The update did
not uninstall the app or reset its container. Signing verification passed.
Install evidence is in `LocalVerification/toolbar-photo-panel-ipad-install.log`
and `toolbar-photo-panel-ipad-install.json`. The app was not launched.
