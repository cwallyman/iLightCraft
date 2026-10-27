# App version cleanup

Completed 2026-10-26 at the user's request to remove other app versions from the
project folder. NativeReference/iLightCraft.xcodeproj is the sole active Apple
app project. This cleanup did not modify either Git history or an installed app.

Moved 39 obsolete source/build items to recoverable Trash:

- The AppleWrapper/LightCraftPad alternate implementation and its build outputs.
- Pre-rebrand source snapshot and legacy Unveil device products/modules.
- Nine old DerivedData folders, including simulators, Mac and release caches.
- The old UnveilEngine XCFramework and fourteen engine build/staging snapshots.
- Superseded 1.0 and 0.14.0 archives, and obsolete top-level Unveil FFI libraries.

Preserved the complete current NativeReference source and Git checkout, embedded
Engine source/current cache, iLightCraftEngine.xcframework and current iOS app
build. The submitted 0.11.0 (1) iOS/Mac archives remain in
LocalVerification/StoreUpload-20261025-v011. All device-backups folders,
verification logs/screenshots, models and originals remain. The parent Rust
LightCraft source/reference and its compilation cache remain for comparison and
source provenance; they are not an alternate native iLightCraft app project.

Recovery location:
`/Users/cwallyman/.Trash/iLightCraft-project-cleanup-20261026-221543`.
The original-to-Trash mapping is recorded in
`NativeReference/LocalVerification/project-cleanup-20261026.json` and in the
Trash folder's RESTORE-MANIFEST.json. Restore individual items to their mapped
original paths only when no newer item occupies that path. Trash was not emptied;
this cleanup removes clutter from the project but does not reclaim that disk
space until Trash is emptied.

The post-cleanup scan found one .xcodeproj, one standalone .app and the two
retained submitted .xcarchive packages. Project/scheme listing and strict signing
verification of the current iOS app passed. Current source, framework and app
paths remain present. No build, simulator, test run or device uninstall was
performed for this cleanup. Historical verification notes may refer to artifacts
that now live in Trash; this record documents that relocation.
