# U2.2 HSL and Profiles — 2026-10-20

First native implementation and device delivery are complete. Hands-on acceptance remains pending.
Point Color, grading wheels and camera-specific calibration remain outside this increment.

## Behavior

- Separate HSL Mixer and Profiles toolbar icons on Mac/iPad, with existing hover labels and right-hand tool docks. iPhone uses More entries and sheets.
- Eight HSL bands: red, orange, yellow, green, aqua, blue, purple and magenta. Each exposes Hue, Saturation and Luminance from -100 to 100 through the existing live draft adjustment queue. Drag release creates one undoable edit. Standard precise values, fine dragging and reset controls are reused.
- Reset current band or all HSL colors preserves unrelated edits. All 24 controls participate in the normal native snapshot values and existing saved settings.
- Profiles exposes the existing engine registry: 22 original built-in looks across Basic, Film, Cinematic, Muted and B&W. Search, favorites and Recent are available; imported engine registry entries also appear if present. No profile import UI or Adobe assets added.
- Profile Amount ranges from 0 to 200 percent and applies on release. Reset restores Color at 100 percent. Selection and Amount use the normal edit queue; full profile ID and Amount are included together in advanced undo settings. Favorites are library preferences, not photo undo entries.
- Dock tools use the main photo. iPhone sheet thumbnails use the shared SDR sRGB export preview after committed edits. Existing final output, catalog persistence and Photos Back-save paths retain full develop settings.

## Evidence

- Debug Mac Catalyst and universal iOS app builds passed (`LocalVerification/mac-install/hsl-profiles-mac.log` and `hsl-profiles-ipad.log`, repository root). No Rust changes or bridge rebuild needed.
- Mac bundle signed, signature verified and installed at `/Applications/iLightCraft.app`. Launched with the original procedural gradient fixture and each panel's diagnostic launch argument. Read-only accessibility and screenshots inspected: all eight HSL choices and three sliders visible; Profiles loaded Color at 100 percent, its registry, groups, stars and search. Both panels reserve space beside the photo. At narrower widths UIKit may place trailing toolbar items in its Overflow menu.
- iPad persistent Application Support backed up before installation. Signed universal bundle installed successfully on paired iPad Air 11-inch (M3). Automatic launch was denied because the device is locked; unlock and open iLightCraft for hands-on checks.
- Added `iLightCraftTests/NativeColorToolsTests.swift`: 24 control mappings/bounds, HSL undo retaining unrelated exposure, profile snapshot inclusion, and real-bridge selection/Amount undo retaining HSL. Tests are saved, unrun and not compiled by the app-only builds, per user preference. No suites or benchmarks run.
- No synthetic UI input, real photo appearance comparison, exported-output comparison, Photos write or physical gesture check performed. Existing unrelated changes preserved; no commit or upstream CI run.

## Saved hands-on checks

1. Open a disposable colorful image. Try all eight HSL bands, drag/precise values/reset and check live photo changes. Undo/redo, reset one band, reset all; check unrelated exposure/crop/masks remain.
2. Select profiles from each group. Change Amount to 0, 100 and 200; verify release-to-apply. Undo Amount separately from selection. Reset to Color.
3. Search and favorite profiles; check favorites and recent choices survive relaunch without adding photo undo steps.
4. Close/reopen and relaunch. Compare the editor with JPEG/TIFF and RAW/HDR output. Verify combined HSL/profile/curve edits persist.
5. Open a disposable Photos image, change HSL/profile and press Back. Reopen and inspect settings, appearance and retained original.
6. Check Mac mouse hover, iPad Pencil hover/touch, iPhone More/sheets, narrow windows, scrolling and accessibility.
