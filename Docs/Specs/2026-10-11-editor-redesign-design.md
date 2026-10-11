# Home and editor redesign

Date: 2026-10-11. Approved in conversation (approach C). Replaces the SwiftUI inspector shell and the alpha
panels with a Pixelmator-like home and editor, sized to the features Unveil has today.

## Constraints

- SwiftUI for layout and state; UIKit only for the Metal canvas, canvas gestures, the Files browser and the
  Photos picker adapters.
- Every user-facing string in English. Native Liquid Glass only (`glassEffect`, glass button styles); never
  tint or change glass opacity: iPadOS 27 manages it system-wide.
- No engine changes. No per-frame SwiftUI state. Frame delivery stays EngineManager → FrameSink → CanvasView.
- One CanvasView and one engine per scene, created once (EditorWorkspace); navigating home and back never
  rebuilds them.
- Accent color: purple, set as the app's AccentColor.
- Reduce Motion: no floating or parallax motion, cross-fades instead of slides.

## Home

- Background: black with a soft purple radial/mesh gradient; "Unveil" title centered in the upper half;
  5 floating photo cards on different depths (scale, blur, shadow, slight `rotation3DEffect`), drifting
  slowly. The cards are the neutral renders of the 5 CC0 RAWs from raw.pixls.us (`Baseline/golden/mac/*__neutral.png`),
  resized to 1024 px JPEG in an asset catalog. Motion is decorative: hidden from VoiceOver.
- Bottom glass panel at half height. Its header holds a segmented picker on the leading side ("Files",
  "Photos") flush with the panel's top edge, and a grabber. Dragging the header or swiping up on the content
  expands the panel to full screen (below the status bar); dragging the header down collapses it.
- Files: the system `UIDocumentBrowserViewController` for opening only (no document creation, single item,
  types `.rawImage` and `.image`), embedded as a child view controller.
- Photos: the system `PHPickerViewController` embedded inline (single selection, images, current
  representation, no library permission), keeping the NSItemProvider path of `PhotoLibraryLoader`.
- Picking from either opens the photo through the existing import path and shows the editor.
- Fallback (approach C): if embedding the Files browser as a child fails on the device, stop and report;
  the coordinator then decides on `DocumentGroupLaunchScene`.

## Editor

- Full-bleed canvas. Navigation from the home is a full-screen swap with a short transition.
- Top leading: back button (to the home), the document title (original file name without the import hash)
  as a menu (Info shows name, pixel size if known, file type; Show in Files and Rename are not available
  yet and are omitted), the status under the title ("Edited" when any control differs from its default,
  otherwise "Original"), and a zoom pill showing the current percentage with a menu: Fit, 100%, 200%.
- Top trailing: Undo, Redo, Share (disabled for now), an ellipsis menu (Reset All; Diagnostics in Debug).
- Trailing tool rail: a vertical glass capsule with Move (hand: canvas pan and zoom only, the default) and
  Adjust (sliders: toggles the adjust card). With an Apple Pencil, fingers always pan and zoom; the rail keeps
  room for Crop, Masks and Heal later (not shown).
- The leading side stays free for a future masks and history panel.

## Adjust card

- A floating glass card left of the rail, full available height minus margins, about 340 pt wide.
- Carousel of pages: Light, Color, Presence, Detail, Effects (AdjustmentGroup order). A strip at the
  bottom of the card names the pages; swiping on the strip or tapping a name changes page with a horizontal
  slide; swiping over the sliders never changes page.
- Custom slider row: name, value, track. Centred controls (range below zero) fill from the default value, not
  from the left. Haptics: selection tick crossing or landing on the default and at the range ends; light
  impact on reset; double tap on the row resets.
- Precision: while dragging, moving the finger vertically away from the track scales the motion to 1, ½, ¼,
  and ⅛ ("Fine") by distance bands; each band change ticks and shows a small label. Tapping the value opens a
  numeric field (clamped, rounded to the step).
- Steppers − / + with haptics; holding repeats as draft previews, and the release sends one full preview.

## Undo and Redo

- App-side, per open photo, in memory: a stack of control-value snapshots recorded at each committed edit
  (slider release, stepper release, reset, value entry, Reset All). Undo and Redo send only the changed
  controls, then one full preview. Opening another photo clears the stacks.
- Engine-side `edit.undo` is not used: its stack is session-wide and also holds imports.

## Testing

- Unit tests: precision band mapping, centred fill geometry, carousel page logic, undo/redo stacks,
  Edited/Original status, title from the picked file name.
- Hosting tests rewritten for the new editor: canvas identity across home ↔ editor and card open/close,
  canvas receives touches with the card closed, alerts visible above the card.
- On the iPad: full test suite, Release install, screenshots of home (half and full panel), editor, card.
