# Adaptive editor controls — 2026-10-20

## Behavior

- iPhone portrait: every tool (including basic Edit, HSL, Profiles, Curves, masks/removal,
  analysis/merge/blur/enhancement, Crop, Export and Info) opens in the lower half of the
  available editor area. The eight-point divider/gap is shared between equal halves.
- Existing scroll views/forms/lists keep the remaining controls reachable inside that panel.
  Tool headers stay in the panel; iPhone no longer presents these tools as full-screen sheets.
- iPhone landscape uses a side panel (right by default); orientation follows available geometry,
  independently of UIKit size classes. iPad/Mac retain side panels.
- More > Settings > Controls side selects Left or Right. The choice is persisted locally per
  device and applies to Edit and all tool docks, including iPhone landscape. Portrait phone
  controls stay below the photo regardless of the saved side.
- The same main Metal canvas stays mounted with pinch zoom/pan and window rendering. No modal
  tool sheet intercepts the photo. Existing operation guards temporarily suspend canvas gestures
  while an edit/analysis/export must finish. Interactive crop/mask/removal previews remain in
  their panels; switching sides changes layout order without relocating the SwiftUI tool identity.
- Permission prompts, source pickers and output sharing can still use system dialogs. Settings
  itself is a separate sheet; it does not replace the selected tool.

## Validation and delivery

Saved layout checks in `iLightCraftTests/EditorControlsLayoutTests.swift` cover equal portrait
allocation, compact landscape placement and persistent side layout on non-phone tall windows.
Tests are saved and unrun; app-only builds do not compile test targets. No suites/benchmarks run.
No app launch, visual capture or physical interaction check performed for this change, at the
user's request. Build and installation results are recorded below separately.

## Hands-on acceptance

1. On iPhone, open every More tool in portrait; scroll to the last control without moving or
   covering the upper photo. Pinch and pan the upper photo, make a change, then inspect detail.
2. Rotate with a tool open; confirm a side panel, usable controls and retained edits/drafts.
3. Select Left and Right in Settings, including with Edit/Crop open. Confirm only the ordering
   changes; close/reopen and relaunch to verify the saved choice on each device.
4. Check iPad rotation/Split View and Mac window sizes, touch/Pencil/mouse, VoiceOver, keyboard,
   safe areas and Photos save-on-Back. Verify busy operation guards still protect changes.

- Mac Catalyst and universal iOS Debug app builds passed. Final signed Mac bundle installed at
  `/Applications/iLightCraft.app` and signature verified. Universal signed build installed on
  the iPhone 17 Pro. Neither app was launched.
- Fresh iPhone/iPad Application Support backup attempts encountered CoreDevice connection
  resets. Earlier backups remain; installation is an in-place app update, with no app data
  removal requested or performed. iPad install outcome follows below.
- iPad Air 11-inch (M3) installation also succeeded. No launch command was issued for any
  device; physical layout/rotation/pinch acceptance is left for the user's testing.
