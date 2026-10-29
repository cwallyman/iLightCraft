# iPad editor redesign — 2026-10-28

The iPad editor uses grouped floating controls and a horizontally scrolling strip with the app's
existing named tool icons. The Adjust dock opens on entering the editor, with a histogram, quick
access to existing tools and rounded adjustment sections. Wide iPad windows add a mask selection
sidebar; the existing mask dock retains all adjustment and creation controls. The photo panel and
library workflows remain in place. Amber is the selection/changed-control color. iPhone and Mac
Catalyst retain their existing layouts.

This is a first implementation based on user-provided inspiration, not evidence of physical-device
acceptance. Inspect layout, text, scroll reachability, mask actions, undo, resize/rotation and photo
interactions on the iPad. No simulator or automated tests were run by request.

The iOS device build and code-signature verification passed. After backing up the existing app
container, the build installed on the paired iPad Air; it was not launched or visually inspected
by the agent. Physical interaction and visual acceptance remain open. The iPhone was not updated.

## Startup crash and fix

The first installed redesign crashed at startup on iPad. Two device crash reports identified
stack exhaustion during SwiftUI type construction in the editor's More menu, reached from the new
iPad toolbar. The menu is now split into smaller, type-erased sections and the toolbar uses a
shallow menu boundary. A focused iPad workspace-launch regression case was added to
`iLightCraftTests/EditorViewTests.swift` and compiled with `build-for-testing`; it was not run.
The replacement iOS build and signature passed and installed on the paired iPad. Device launch and
process listing succeeded, and the user confirmed the app is running. This does not establish
acceptance of every editor interaction or visual detail.

## Follow-up changes (2026-10-29)

Iterated from the user's iPad screenshots: Profiles, Color Grading, Crop, Masks and Remove now
use the card style, and the photo surround is black. The left mask sidebar was removed; Add Mask
opens a pop-out in the right panel. Opening Masks or Remove then crashed with stack exhaustion
while SwiftUI resolved the panel's view type (two device crash reports). The Masks, Remove and
Analysis sections are now type-erased. The fixed build was installed and the user confirmed
both panels open. No simulator or automated tests were run.
