# Right-side tool dock — 2026-10-20

Mac and iPad now route Tone Curves, all six computational tools, Crop & Rotate, Export and
Info into a single reserved dock to the right of the photo. Edit uses the same right-side
layout; choosing another tool closes Edit, choosing Edit replaces the tool, and clicking
the active tool again closes it. The existing Metal canvas remains mounted and resizes.
iPhone keeps modal tool presentation and the compact Edit layout.

The dock is 280–360 points wide. It has its own title and Done/Cancel/Close actions. The
initial nested NavigationStack experiment merged tool actions into the main toolbar; docked
tools now use an explicit local header, with the navigation presentation retained for iPhone.
Long-running analysis/render/export/apply operations disable tool switching, Back and canvas
interaction until they finish, while the panel's own cancellation remains available.

Tone Curves uses the large main photo and omits its duplicate preview in the dock. Crop,
Masks and Remove retain their interactive previews inside the dock; crop handles, object
picking, mask overlay and removal strokes operate on those previews. File pickers, permission
alerts and system sharing can still use platform dialogs. Masks use a two-column text layout
so long choice names fit the narrow panel.

Evidence:
- Mac Catalyst and universal iOS builds passed.
- Mac installed/signed/signature verified and launched with the procedural gradient fixture.
  Read-only screenshots/accessibility inspection confirmed Tone Curves and Masks to the right,
  a resized visible photo, local dock actions, and an intact main toolbar. The first mask
  screenshot exposed narrow wrapping; grid/font/label treatment was then corrected.
- iPad persistent Application Support backed up before update; delivery results below.
- Updated saved EditorViewTests for the device-based layout and added an actual hosted-layout
  regression verifying an Info tool reserves canvas width without recreating the Metal view.
  Tests are saved, not run or compiled by app-only builds, per user preference.
- No full suite, benchmark, real-photo editing/output/Photos round trip, physical pointer/Pencil
  check or upstream CI performed. No commit made; existing work preserved.

Saved acceptance: switch among every tool and Edit; close/reopen; portrait/landscape and narrow
windows; crop Cancel/Done; mask/remove preview input; export cancellation/share; no main-toolbar
mixing; no photo overlap; busy operations block switching and return to normal on completion.

Delivery: final signed iPad app installed successfully; automatic launch was blocked by the
device lock. Final Mac app signature verified, installed and process confirmed. The final
Masks screenshot was visually inspected after the two-column text-label correction; names
fit without broken-word wrapping and the large photo remained unobstructed.

## Active toolbar highlight — 2026-10-20

Edit, HSL, Profiles, Curves, computational tools, Crop and Export now use explicit selected
foreground, a rounded background/outline and selected accessibility traits while their dock
is open. The same style marks HDR/Show Original when enabled. Styling is applied inside the
custom hover host so it does not depend on inherited toolbar tint crossing UIHostingController.
Selection follows existing panel state and clears when closed/replaced. iPhone retains menu
presentation without the toolbar background treatment.

Mac Catalyst and universal iOS Debug builds passed. Signed Mac update installed and launched;
read-only accessibility confirmed selected HSL and screenshot inspection confirmed the active
Profiles icon uses an amber symbol and rounded selection outline, with inactive peers unselected.
iPad Application Support backed up before the signed update. No automated tests or benchmarks run.
