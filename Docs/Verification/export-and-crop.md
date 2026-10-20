# Native export and crop

Last updated: 2026-10-19. Roadmap tasks U1.1/U1.2 (user list items 2 and 3).

## Implemented

- Export button on iPhone/iPad/Mac, with the native system share sheet and Save to Files.
- JPEG quality; PNG/TIFF 8/16 bit; full size or long-edge resizing; sRGB, Display P3,
  Adobe RGB compatible, ProPhoto and Rec.2020; metadata policy/location removal, output
  sharpening and text watermark. Batch selection lists imported catalog photos, loading pages
  explicitly. Exports run sequentially with progress and a stop-after-current-photo control.
- Files are rendered by the shared Rust engine, never captured from the display. Output uses
  a unique temporary directory and refuses to overwrite any existing file or catalog original.
- More > Crop & Rotate presents an uncropped rendered preview, draggable corner handles and
  crop positioning; free/original/square/4:5/5:7/2:3/4:3/16:9 presets, portrait/landscape,
  90-degree left/right rotations, horizontal/vertical flips and ±45-degree straightening.
- Crop drafts are local until Done; Cancel preserves the prior settings. Done constrains the
  crop within the source image and joins native undo/redo. Preview and export share settings.

## Saved automated tests (not run)

From `Engine`:

```sh
cargo test --locked -p unveil-ffi --test native_output
```

Saved Swift tests: `UnveilTests/CropSettingsTests.swift` (orientation and settings round-trip).
Existing editor undo tests should also be run when testing is requested. No automated test suite
was run for this change, following the user's request to leave testing to them.

## Hands-on acceptance

- [ ] Open a photo on iPhone, select More > Crop & Rotate, drag corners and move the crop.
- [ ] Select portrait and landscape presets; rotate left/right, flip both axes and straighten.
- [ ] Cancel a draft; confirm it changes nothing. Apply; undo/redo; close/reopen and relaunch.
- [ ] Export JPEG/PNG/TIFF; open in Photos or another decoder and compare crop/color/details.
- [ ] Check quality, resize, color spaces, 16-bit output, metadata/location removal and watermark.
- [ ] Select several imported photos, export, stop after the current photo and share completed files.
- [ ] Use Save to Files and verify originals are untouched; check storage/permission errors.
- [ ] Verify iPad and Mac layouts and share destinations separately.

## Packaging evidence

- Rust release engine framework built for iOS device, simulator and Mac Catalyst.
- Final unsigned iOS device and simulator app builds passed; device app development-signed.
- Current app container backed up before updating the paired iPhone 17 Pro. The update was
  installed and launch confirmed by devicectl under `com.cwallyman.UnveilNative`.
- Simulator crop preview rendered the original generated color chart; screen captured and
  visually inspected. Corners, grid, rotation, flips, aspect and straighten controls are visible.
- Export screen captured and visually inspected: file and finishing options, batch-photo
  selection and Export/Close controls are readable without overlap. No automated test suite was run.
- Physical crop gestures, actual exported file inspection, undo/redo and relaunch persistence
  remain user checks. Mac/iPad app runtime was not checked for this change.

Logs: `/tmp/unveil-export-framework-final.log`, `/tmp/unveil-export-device-final.log`,
`/tmp/unveil-export-sim.log`, `/tmp/unveil-export-iphone-install.log`,
`/tmp/unveil-export-iphone-launch.log`. Screenshots are local-only in the parent workspace's
`LocalVerification/unveil-crop-screen.png` and `LocalVerification/unveil-export-screen.png`.
