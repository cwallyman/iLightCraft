# iLightCraft

Native photo editing for **iPhone, iPad and Mac**, built with SwiftUI, UIKit/Metal and the
LightCraft Rust engine. Based on [Unveil](https://github.com/eliorodr2104/Unveil).
The app uses LightCraft amber-yellow (`#F2A516`) and a floating winking lynx above its name.

**Development status:** HEIC, export and crop milestones received user acceptance. RAW/HDR
and Apple Photos editing are implemented; ARW routing and a Photos save crash have been
corrected and delivered to iPhone. Their complete device round trips still need confirmation.
Priority 4 now has a first native **on-device tools** implementation for items 18–23. Several advanced
subfeatures and real-output acceptance remain; see the [implementation/acceptance table](Docs/Verification/priority4-on-device.md).
This is not a claim of Lightroom parity or App Store readiness.

Point Color, grading, optics, manual masks, repair refinements, presets/batch, versions/history and portable backup/restore now have native workflows. Physical acceptance is pending; [scope and limits](Docs/MISSING-FEATURES.md).

## Documentation

- [App Store preparation](Docs/APP-STORE-READINESS.md): branding exceptions, Release packaging and remaining submission work.
- [Xcode Cloud setup](Docs/XCODE-CLOUD.md): generated engine/model inputs and Apple/GitHub workflow setup.

- [Next steps](Docs/NEXT-STEPS.md): immediate checks, every remaining feature and release work.
- [Full prioritized roadmap](Docs/Plans/2026-10-19-lightroom-priorities.md): task IDs and detailed scope.
- [Change history](CHANGELOG.md): all native iLightCraft changes since the upstream native baseline.
- [Verification notes](Docs/Verification/): build, visual, device and saved-test evidence.
- [Artwork attribution](assets/ATTRIBUTION.md), [engine modifications](Engine/CHANGES.md)
  and [engine upstream revision](Engine/UPSTREAM.md).

## Current capabilities

| Area | Native workflow | Evidence and limits |
|---|---|---|
| Layout | iPhone portrait lower-half tools, landscape side tools; selectable left/right side on all devices; scrollable controls and pinch/pan canvas | App builds passed; installed without launch by request; adaptive layout hands-on checks pending |
| Import | Files/Photos browser; HEIC/HEIF decoder enabled in shared Rust builds | HEIC milestone accepted; extended checks saved |
| Tone Curves | RGB/red/green/blue point curves, drag/add/delete, precise coordinates, channel resets and undo | Mac/iOS builds passed; installed on Mac/iPad; Mac sheet visually reviewed; round-trip/output acceptance pending |
| HSL / Profiles | Eight HSL color bands with Hue/Saturation/Luminance; 22 built-in profiles, Amount, search, favorites and recent choices | Mac/iOS builds passed; Mac dock visually reviewed; hands-on persistence/output acceptance pending |
| Editing | Existing basic adjustments, undo/redo and before/after; added native crop controls | Export/crop milestone accepted |
| Crop | Handles, positioning, ratio presets, rotation, flips and straightening | Preview reviewed; detailed gesture/persistence checks remain |
| Export | JPEG/PNG/TIFF, quality/size/color/depth options, metadata/location policy, sharpening, text watermark and batch sharing | UI reviewed and milestone accepted; detailed output checks remain |
| RAW/HDR | Apple full-resolution RAW decode, gain-map expansion, float working copies, EDR canvas and HDR TIFF/HEIC export | Builds and synthetic HDR preview reviewed; physical camera/HDR checks pending |
| Photos saving | Explicit same-item save, complete adjustment settings, revision checks and local-version recovery | Callback crash corrected and installed; save/reopen/conflict acceptance pending |
| On-device masks/removal | Subject/background/people/object masks, exposure/colorize/skin-tone controls/combine/refine; brush-based patch healing; saved settings/undo | Simulator screen reviewed; selection/removal quality and persistence acceptance pending |
| AI enhancement/Lens Blur | Optional pinned local Core ML RGB denoise/2× enhancement and depth-based TIFF blur copies | Builds passed; actual model inference/quality pending; no sensor-domain Raw Details |
| Library analysis | Local labels/OCR/face count, imported-photo index, keyword/local label-text vector search | No identity recognition or joint image-text model; bounded private index |
| Photo merge | Ordered HDR/panorama/HDR-panorama jobs, deghost/projection/crop, cancel/memory guard and new DNG | Builds passed; real source/output acceptance pending |
| Branding | iLightCraft name, yellow accents, winking lynx icon and floating home logo | Simulator reviewed; iPhone update installed and launched |

An engine capability is not automatically an exposed or verified native app feature.

## Using the app

1. Choose **Files** or **Photos** and open a still image. Grant Photos access yourself when requested.
2. Use **Edit/Done** to show or hide adjustments.
3. For Masks, Remove and Crop & Rotate, interact directly with the main photo; pinch to zoom and use two fingers to pan. Their panels contain the controls. Use **HSL Mixer** for eight color bands and **Profiles** for built-in looks and Amount (0–200%). Open these from the Mac/iPad toolbar or iPhone More menu. Use **Tone Curves** in the Mac/iPad toolbar (or iPhone **More**) for RGB and individual-channel curves. Tools open beside the photo on Mac/iPad and iPhone landscape; iPhone portrait uses a scrollable lower-half panel with the main photo available for pinch zoom. More > Settings > Controls side chooses Left or Right for side panels. Tap to add a point, drag it and release to update the photo; use the point selector and Input/Output sliders for precise changes.
4. Use **More > Crop & Rotate** for crop handles, presets, rotation and straightening.
4. Use **More > HDR Editing** to control HDR processing; native RAW/HDR imports enable it by default.
5. Use **Export** for output options, batch selection and the system share sheet/Save to Files.
6. On Mac/iPad, use the toolbar icons for Masks, Remove, Library Analysis, Merge, Lens Blur and AI Enhancement. On iPhone, find them in **More**. Hover an icon to see its label.
   Depth/enhancement models download only when you choose Download; photos stay on device. Lens Blur
   and enhancement create rendered copies. RGB enhancement requires explicitly disabling HDR Editing.
7. For an image opened from Photos, choose **More > Save to Apple Photos** to request a save to that item.
   If Photos changed externally, keep the local edit or use **Reload Latest Photos Version**.

Local drafts are retained while editing. For a photo opened from Apple Photos, **Back** waits for pending edits and saves changed settings/rendering to the same Photos item before returning home. A save failure or external-edit conflict keeps the editor open. Manual **Save to Apple Photos** remains available. Originals are retained by the import/save design; preservation and round-trip checks
are listed in the verification documents.

## Build

Requires macOS, Xcode with the iOS/iPadOS 26 APIs, Rust/Cargo and the Apple Rust targets below.
Deployment starts at iOS/iPadOS 26. Current Mac Catalyst engine slices target Apple silicon;
Intel Mac support is not included and Mac runtime compatibility remains a verification task.

```sh
git clone https://github.com/cwallyman/iLightCraft.git
cd iLightCraft
rustup target add aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-ios-macabi
scripts/build-xcframework.sh
# In a Python venv, prepare the bundled sky/skin models once:
pip install -r scripts/mask-model-requirements.txt
python scripts/build-mask-models.py
scripts/build-apple-local.sh simulator
scripts/build-apple-local.sh ios
scripts/build-apple-local.sh mac
```

The framework command builds device, simulator and Mac Catalyst Rust slices. The app commands
build unsigned products in `DerivedData-Apple-<platform>`; they do not install them. Device
installation requires your development team, provisioning profile and signing identity.
See [local iPad notes](Docs/LOCAL-IPAD.md) for the earlier machine-specific helpers.

The Xcode project, scheme and Swift module are now `iLightCraft`; the displayed name is **iLightCraft**.
Release uses `com.cwallyman.iLightCraft`. The Debug helper reads an optional ignored `Config/DevelopmentIdentity.xcconfig` to update existing test installs; `ILIGHTCRAFT_BUNDLE_ID` can override it.
Existing wrapper/prototype libraries are separate; no automatic migration or deletion occurs.

## Next steps

First confirm the installed **ARW import and Photos save fixes**, including full-resolution
output, original preservation, saved settings, relaunch and conflict recovery. The user moved **Priority 4 (items 18–23)** ahead of the core-tools queue. Finish its missing subfeatures
and acceptance checks, then resume the remaining priorities:

1. **Core tools:** tone curves, advanced color, optics/perspective, local masks, healing,
   presets/batch editing and versions/history.
2. **Library/devices:** organization, search/culling, metadata editing, optional CloudKit sync,
   backup/restore and migration.
3. **Computational tools:** semantic masks, AI enhancement, Lens Blur, advanced removal,
   intelligent library search and HDR/panorama merge.
4. **Specialist workflows:** hosted sharing/web access, video/Live Photos, tethering, maps,
   print/presentation, publishing/extensions and learning/community.
5. **Release work:** platform/accessibility checks, memory/performance measurement, recovery,
   privacy, signing and packaging.

The [next-steps checklist](Docs/NEXT-STEPS.md) includes every remaining roadmap item and
acceptance work. Priority 4 is partially implemented; remaining subfeatures stay unchecked.

## Verification and limitations

- Native engine builds passed for device, simulator and Mac Catalyst. Recent iPhone and simulator
  app builds passed; the latest update was signed, installed and launched on the paired iPhone 17 Pro.
  Successful build/install/launch does not establish successful Photos saving.
- Simulator crop, export, synthetic HDR, branding and Priority 4 tool-screen captures were visually inspected. Captures
  and backups remain local. An SDR screenshot cannot prove real EDR brightness.
- The initial HEIC phase completed a Rust bridge suite before testing was paused. Subsequent
  suites and benchmarks are **saved, not run**, at the user's request to conserve credits.
- RAW support/color follows Apple's installed decoder, not universal camera compatibility or
  Lightroom-identical rendering. The native 80-megapixel cap and memory guard do not guarantee
  every file below that cap fits a particular device.
- Same-item Photos editing handles still images; Live Photos/video are rejected. The separate
  wrapper's private CloudKit sync has not been migrated.
- Current iPad/Mac workflows and complete RAW/HDR/Photos acceptance remain outstanding.

Evidence: [HEIC](Docs/Verification/heic-support.md), [export/crop](Docs/Verification/export-and-crop.md),
[RAW/HDR/Photos and fixes](Docs/Verification/raw-hdr-photos.md), [branding](Docs/Verification/ilightcraft-branding.md).

## Source and licenses

Repository: [cwallyman/iLightCraft](https://github.com/cwallyman/iLightCraft). Default branch:
`ipad-lightcraft`. Native baseline: `79be4e4`; first combined implementation: `2f71fe9`.
Original upstream history and its remote are preserved.

Source, asset licenses, development notes and saved tests are published. Generated frameworks,
build products, provisioning material, real camera fixtures, personal libraries and backups are
excluded. Never commit personal media or signing credentials.

Licensed under [Apache-2.0](LICENSE); see [NOTICE](NOTICE), [asset attribution](assets/ATTRIBUTION.md)
and the vendored engine's notices for component terms. Optional model sources, exact revisions, SHA-256
pins, license texts and privacy/output limits are documented in the [model catalog](Docs/Models/README.md).
