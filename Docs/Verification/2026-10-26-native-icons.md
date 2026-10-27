# Native LightCraft icon consistency

Updated 2026-10-26. All app-owned SF Symbol references in Swift sources were
replaced by LightCraft's original desktop vector icon catalog. This covers the
editor toolbar, menus, tool panels, navigation, empty states, home Files controls,
Photos browser and diagnostics. Apple's system-owned document/share UI and the
existing iLightCraft lynx branding retain their own artwork.

The 82 original desktop icons plus a clipping triangle and mirrored clockwise
rotation arrow are scalable template PDFs. Their pinned source, source SHA-256,
licenses, generator and semantic mappings are in `scripts/icon-tools/`.
Labels, tooltips, keyboard shortcuts, identifiers, actions and selection bindings
are preserved. Before/After uses the desktop BeforeAfter icon.

## Verification

- `python3 scripts/tests/test_lightcraft_icons.py`: 2 tests passed. Verifies
  complete source catalog/provenance, vector/template metadata, PDF dimensions,
  every literal Swift asset reference, and absence of SF Symbol references.
- Debug iOS Simulator build: passed, including a final incremental build after
  the Before/After correction. Logs: `LocalVerification/icons-simulator-final.log`.
- Debug iOS device build, unsigned: passed. Log:
  `LocalVerification/icons-ios-build.log`.
- All 84 exported PDFs rendered to a contact sheet and visually inspected:
  `LocalVerification/lightcraft-icon-catalog.png`. Paths, orientation, stroke
  consistency, dotted masks, gradients and filled states render correctly.
- `git diff --check`: passed.
- Simulator installation stalled and a bounded retry timed out. A running-app
  screenshot and physical-device acceptance are not verified. No App Store upload was performed. Full Rust engine CI was not run: the engine
  is unchanged, and no commit was created.

## Physical iPad delivery

At the user's request, rebuilt Debug for the existing iPad development identity
`com.cwallyman.UnveilNative` using `Config/DevelopmentIdentity.xcconfig`.
Build and strict code-sign verification passed. `devicectl` confirmed **App
installed** on the paired iPad Air 11-inch (M3), an in-place update without
uninstalling the app or removing its container. The app was not launched.
Logs: `LocalVerification/icons-ipad-final-build.log`,
`LocalVerification/icons-ipad-install.log` and `icons-ipad-install.json`.
The pre-update Application Support backup copied data but timed out after 45
seconds; it is incomplete and is not counted as a verified backup. Hands-on icon
and library acceptance remain unverified.
