# Mac home screen — 2026-10-20

Mac Catalyst now uses a home view in the app window rather than UIDocumentViewController,
which presented a separate Open dialog at startup. The Mac home reuses HomeBackground
(lynx, title, amber contours), CapsulePicker and PhotosBrowser. Files offers an explicit
Browse action using the system file importer; it does not reproduce the iPad system Recents
grid. Import callbacks still pass through the existing security-scoped importer. Errors
appear in an alert. iPhone/iPad keep their document-launch home.

Verification: Mac Catalyst and universal iOS Debug builds passed. Installed and signed
/Applications/iLightCraft.app, verified its signature, and relaunched. Read-only accessibility
inspection confirmed the branded home, Files/Photos controls and Browse actions, without
an Open dialog. The running Mac screenshot was visually inspected: logo/title and lower
panel are visible with no overlap. Photos permission/import and file selection round trips
remain hands-on checks. No full test suite, upstream CI or commit performed.
