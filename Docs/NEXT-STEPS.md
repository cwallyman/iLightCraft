# iLightCraft next steps

Last updated: 2026-10-28. Development branch: `ipad-lightcraft`.
The [full roadmap](Plans/feature-priorities.md) defines task scope;
the [change history](../CHANGELOG.md) records implementation so far.
See the [prioritized missing-feature list](MISSING-FEATURES.md) for a concise implementation queue and the [comparison with other photo editors](OTHER-PHOTO-EDITORS-COMPARISON.md) for a feature checklist.
App Store identity/packaging work is recorded in [App Store readiness](APP-STORE-READINESS.md); unsigned Release archives passed on 2026-10-21, while distribution signing and physical acceptance remain.
Unchecked implemented work still needs acceptance. Build, install, visual and physical evidence differ.

## 1. Confirm installed reliability fixes first

Use disposable still images and user-granted Photos access; preserve originals and drafts.

- [ ] Reopen the affected Sony ARW from Files and Photos. Check full-resolution detail, color,
  orientation, zoom and an exposure change. Record camera/file variant and installed OS.
- [ ] Save an edit to the same Photos item. Confirm no crash, no duplicate and a visible result in Photos.
- [ ] Reopen and relaunch; check image appearance, crop, sliders, saved settings and RAW/HDR state.
- [ ] Revert the disposable Photos item and confirm the original remains available.
- [ ] Modify the item externally while a draft exists. Confirm overwrite is blocked, Keep Local Edit
  retains the draft and Reload Latest preserves the previous local version.
- [ ] Check denial/limited access, iCloud download failure, offline state and low storage.
- [ ] Record results in [RAW/HDR/Photos verification](Verification/raw-hdr-photos.md).
  Complete U1.3/U1.4 only after their acceptance checks pass.

The ARW and Photos callback corrections are installed. Successful build/install/launch alone
must not be recorded as affected-camera decoding or a successful Photos round trip.

## 2. Finish output and platform acceptance

- [ ] Compare HDR Editing on/off with known HDR media; check real device display headroom.
- [ ] Export HDR float TIFF and 10-bit HEIC; inspect in another HDR-aware viewer.
- [ ] Check camera variants, unsupported-file errors and large-file memory behavior within the
  native 80-megapixel cap. Do not substitute a preview for full RAW decoding.
- [ ] Complete HEIC orientation/color, corrupt-input, reopen/persistence and unchanged-original checks.
- [ ] Complete crop/export edge cases: presets, rotate/flip, Cancel, undo/redo, reopen, output crop,
  quality/depth/color, metadata/location, watermark, batch stop and sharing/storage errors.
- [ ] Install current source on iPad: portrait/landscape, safe areas, touch/Pencil, viewport,
  Photos and sharing. Verify the new branding separately.
- [ ] Run signed Mac Catalyst: window resizing, keyboard/pointer, EDR, permissions and exports.
  Establish supported macOS versions. Intel support is not implemented.
- [ ] Confirm the icon/name, yellow accents and floating logo on physical devices, including
  Reduce Motion, background/foreground behavior and expanded library panels.

HEIC and export/crop already received general user acceptance; these are remaining detailed checks.

## 3. Remaining feature queue

The user moved **Priority 4 / items 18–23** ahead of tone curves and advanced color. Its first native
on-device implementation is now available; finish the remaining subfeatures and device acceptance in
[Priority 4 verification](Verification/priority4-on-device.md). Keep the six rows partial until their scope
and acceptance are complete. The user's policy is on-device processing first; hosted sharing stays separate.
All remaining agreed tasks are listed here; details and dependencies are in the full roadmap.

| Priority | Task | Native work and acceptance target |
|---|---|---|
| P2 | U2.1 Tone curves | Implemented and installed: RGB/channel point graph, precise controls, reset and undo; hands-on persistence/export/Photos acceptance pending |
| P2 | U2.2 Advanced color | HSL and built-in creative profiles implemented; hands-on acceptance pending. Point Color, grading wheels, camera-specific calibration and extended output checks remain |
| P2 | U2.3 Optics/geometry | Lens matching/profiles, distortion, aberration, defringing, perspective and Upright |
| P2 | U2.4 Manual masks | Brush/gradients, color/luminance range, combine/refine/feather and Pencil input |
| P2 | U2.5 Healing/cloning | Spot/brush selection, source choice, restore/undo, progress and cancellation |
| P2 | U2.6 Presets/batch edits | Save/apply/import/favorite presets and selective copy/paste across photos |
| P2 | U2.7 Versions/history | Named versions/snapshots, alternate copies, persistent history and compare/reference |
| P3 | U3.1 Organization | Albums/collections, smart collections, stacks, ratings, flags, labels and keywords |
| P3 | U3.2 Search/culling | Metadata filters, saved searches, multi-selection and side-by-side comparison |
| P3 | U3.3 Metadata | Captions, copyright, keywords, IPTC/GPS, capture times and sidecar/interchange |
| P3 | U3.4 Device sync | Optional private CloudKit sync, originals/edits, offline recovery and two-device conflicts |
| P3 | U3.5 Backup/migration | Native backup/restore and supported catalog import from other photo editors with unsupported-settings reports |
| P4 | U4.1 Semantic masks | Subject/sky/background/object/people/landscape/depth, refinement and recomputation |
| P4 | U4.2 AI enhancement | Licensed Denoise/Raw Details/Super Resolution models, setup/progress/cancel |
| P4 | U4.3 Lens Blur | Depth/focus range, blur/bokeh and depth refinement |
| P4 | U4.4 Advanced removal | Content-aware/generative removal, distractions, reflections and background people |
| P4 | U4.5 Intelligent library | Faces, content/natural-language search and explicit model policy |
| P4 | U4.6 Photo merge | HDR brackets, panorama/HDR panorama, alignment, deghosting, projection and memory limits |
| P5 | U5.1 Hosted sharing/web | Shared links, invitations, collaboration, comments/likes and web access |
| P5 | U5.2 Video/Live Photos | Playback, trim, color/export and paired-resource preservation |
| P5 | U5.3 Tethering | Cameras, connection recovery, watched folders and import presets |
| P5 | U5.4 Maps | Map browsing, drag-to-geotag and saved locations |
| P5 | U5.5 Print/presentation | Soft proofing, print/book layouts, slideshows with titles/music and export |
| P5 | U5.6 Publishing/extensions | Publish queues, galleries, external-editor round trips and extension interfaces |
| P5 | U5.7 Learning/community | Guided help, tutorials, shared edits and presets if hosting is adopted |
| Future | U5.8 MCP integration | Explore a local MCP server for Mac Catalyst connected to the active native editor session, with explicit access controls and safe command handling; determine iPhone/iPad feasibility separately |

P4 rows are partially implemented; the table describes full task scope. Other unchecked rows remain plans. Adaptive presets depend on semantic masks;
face/semantic search depends on U4.5. Hosted work needs a service design. AI requires permissive
model licenses, setup/download policies, resource budgets and clear failure/cancellation behavior.

Tone Curves and the other editor tools use a reserved side panel on Mac/iPad and iPhone landscape, with left/right selection in More > Settings. iPhone portrait uses a scrollable lower-half panel; tool entries remain in More. See [adaptive controls](Verification/adaptive-controls.md). See [dock verification](Verification/right-tool-dock.md). Tone Curves is available from the Mac/iPad toolbar and iPhone More menu. **U2.2 Advanced Color** now exposes HSL and built-in creative profiles; Point Color and color-grading wheels remain next. See [color tools evidence](Verification/hsl-profiles.md). See [Tone Curves evidence](Verification/tone-curves.md).

## 4. Saved tests for the user

**Do not run suites or benchmarks automatically.** The user asked to keep them for manual use
to conserve credits. This documentation update does not resume testing.

| Area | Saved checks |
|---|---|
| HEIC | `Engine/ffi/tests/heic.rs`, `iLightCraftTests/HEICImportTests.swift` |
| Export/crop | `Engine/ffi/tests/native_output.rs`, `iLightCraftTests/CropSettingsTests.swift`, editor undo/layout tests |
| RAW/HDR | `Engine/ffi/tests/hdr_output.rs`, `iLightCraftTests/NativeImagePipelineTests.swift`, ABI/canvas tests |
| Photos | `iLightCraftTests/PhotosAdjustmentTests.swift`, importer/cleanup and saved-settings checks |
| Priority 4 | `Engine/ffi/tests/computational.rs`, `iLightCraftTests/ComputationalToolsTests.swift`; real model/merge checks in verification notes |
| Tone curves | `iLightCraftTests/ToneCurveTests.swift`; saved manual checks in `Verification/tone-curves.md` |
| HSL / Profiles | `iLightCraftTests/NativeColorToolsTests.swift`; saved manual checks in `Verification/hsl-profiles.md` |
| Existing behavior | Existing editor, import, engine, canvas and memory tests |

When requested, run the following from `Engine`:

```sh
cargo test --locked -p ilightcraft-ffi --test heic
cargo test --locked -p ilightcraft-ffi --test native_output
cargo test --locked -p ilightcraft-ffi --test hdr_output
cargo test --locked -p ilightcraft-ffi --test computational
cargo test --locked -p ilightcraft-ffi --features test-hooks
```

Before Swift integration tests, rebuild the current engine from the repository root:

```sh
scripts/build-xcframework.sh
scripts/test-app.sh
```

The camera RAW test requires `ILIGHTCRAFT_RAW_FIXTURE` pointing to a suitable local fixture.
The Photos queue-crash test is opt-in: set `ILIGHTCRAFT_RUN_PHOTOS_SAVE_REGRESSION=1` in the test
scheme and grant the test host Photos read/write access yourself. It creates, edits and deletes
its own generated asset. It must not select personal media. See verification notes for prerequisites.
Benchmarks and measured rendering comparisons with other photo editors remain pending.

## 5. Cross-cutting and release work

- [ ] Measure slider/zoom/export latency, memory peaks and battery/background use on target hardware;
  include repeated large RAW/HDR open/save/export and low-memory recovery.
- [ ] Verify VoiceOver, Dynamic Type, contrast, Reduce Motion, touch targets, Pencil and keyboard input.
- [ ] Verify malformed files, corrupt catalogs/caches, disk-full, interrupted saves and conflicts;
  errors must preserve originals and recoverable drafts.
- [ ] Establish native backup/restore and user-controlled migration before sync/release.
- [ ] Measure per-model camera/color/output behavior before making coverage/rendering-parity claims.
- [ ] Audit licenses/notices and privacy disclosures; keep personal media, credentials and backups out of Git.
- [ ] Establish distribution signing/entitlements, production services where used, TestFlight/App Store
  packaging, store assets and an accurate supported-platform description.
- [ ] Update README, changelog, roadmap and evidence after each accepted milestone; record device results separately.

The separate wrapper's archives/sync evidence do not establish native release readiness.
No native App Store submission or automatic wrapper-library conversion has occurred.

## Revision history

- 2026-10-20: Moved Priority 4 ahead by user request; linked partial implementation, local model policy and saved checks.

- 2026-10-20: Added native Tone Curves implementation/delivery evidence; retained acceptance checks and advanced color as the next core addition.

- 2026-10-20: Added native HSL and Profiles, build/delivery evidence and saved checks; retained remaining U2.2 scope and hands-on acceptance.

- 2026-10-20: Added iPhone lower-half/landscape side tool docks and More > Settings placement on all devices; see [adaptive controls](Verification/adaptive-controls.md). Physical acceptance remains pending; no apps launched by request.

- 2026-10-20: Moved Masks/Remove/Crop interaction into the main photo and reordered core tools; see [main-photo evidence and preview limits](Verification/main-photo-tools.md). Physical checks remain pending; no launches by request.

- 2026-10-20: Added independent per-mask color/skin-tone controls and quick colorize swatches; see [mask-color verification](Verification/mask-color.md). Physical/output acceptance remains pending.

## Remaining-feature update — 2026-10-20

Native first passes for missing-feature queue 1–7 and portable backup/restore are implemented. Items 8 and 9 remain skipped. CloudKit is deferred by user. See [missing-feature status](MISSING-FEATURES.md) and its verification record for limits and acceptance work.
