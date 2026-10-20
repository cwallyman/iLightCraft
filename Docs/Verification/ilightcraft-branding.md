# iLightCraft native branding

Updated 2026-10-19.

The home screen now shows the existing winking lynx artwork above iLightCraft.
The five floating sample photos are no longer used on home. A Core Animation
layer gives the logo a gentle vertical float, pauses while covered/inactive,
and remains still for Reduce Motion. The layout fits above the library picker
using the actual resting panel position.

Accent color is LightCraft amber, #F2A516, from the upstream app icon README.
CFBundleDisplayName and Photos permission messages use iLightCraft. The app
icon uses the existing winking lynx. Asset provenance and license are in
assets/ATTRIBUTION.md and Docs/Branding/. Existing app identity is preserved.

iPhone and simulator builds passed. The iPhone simulator home screenshot was
visually inspected: logo and title are visible above the source picker without
overlap, and selected Files/Recents controls use yellow. Screenshot in parent
workspace: LocalVerification/ilightcraft-home-iphone.png.
No automated tests were run. Physical appearance and motion acceptance remain
with the user.

The final signed build was installed and launched successfully on the paired
iPhone 17 Pro. Persistent Library data, including originals, editing copies and
catalog drafts, was backed up successfully before installation to
`LocalVerification/device-backups/iphone-before-ilightcraft-branding-library-20261019`
in the parent workspace. The earlier whole-container transfer timed out/interrupted;
only this completed persistent-library backup is counted for this update.
