# Priority 4 on-device tools: implementation and acceptance

Last updated: 2026-10-20. User scope: items 18–23 (U4.1–U4.6); on-device processing first.
Hosted sharing is item 24 / U5.1 and is outside this update. No Priority 4 task is marked complete.

Open a still image, then use the separate tool icons on Mac/iPad or the named entries in More on iPhone. Each opens its own section; the in-sheet selector remains available.

## Implemented and remaining scope

| Item | Implemented first pass | Still required |
|---|---|---|
| 18 U4.1 Semantic masks | Apple Vision subject/background/people, separate person instances, bundled sky and per-person skin masks, tap-selected foreground instance; normalized saved coverage; exposure, temperature/tint/hue/saturation and colorize; add/subtract/intersect, invert, delete, edge refinement; native undo/redo | Landscape/additional body-part/depth masks, general object prompting, durable recomputation/status, adaptive profiles/presets; real selection/output acceptance |
| 19 U4.2 AI enhancement | Optional pinned BSD Core ML RGB denoise and 2× Super Resolution; bounded padded tiles; progress/cancel; separate SDR PNG | Sensor-domain AI denoise, Raw Details, input coverage, actual inference/quality/seam/color acceptance |
| 20 U4.3 Lens Blur | Optional pinned Apache local depth model; relative focus/range and blur strength; separate float TIFF copy | Editable depth/blur layer, bokeh shapes, depth preview/paint refinement; real model depth/output/HDR acceptance |
| 21 U4.4 Advanced removal | Native normalized brush stroke, content-aware automatic source-patch healing, persisted engine spot settings and undo | Generative fill, reflection removal, automatic distraction/background-person detection; real patch-quality acceptance |
| 22 U4.5 Intelligent library | Image labels, OCR, face counts; sequential imported-catalog index with cancellation/atomic saves; keyword/English label-text semantic search; open local draft; clear private index | Face identities/clusters, joint image-text content model, whole-library scalable index and quality/privacy acceptance |
| 23 U4.6 Photo merge | Ordered 2–12 sources; HDR, panorama, HDR panorama; alignment, deghost, projection/auto-crop controls; bounded output/memory, background cancel, new unique DNG | Real exposure/geometry/deghost/color/large-file acceptance and source-group/result UX refinement |

Masks and healing use the shared engine renderer and remain in adjustment settings. Native undo snapshots now
capture masks/spots/red-eye/lens-blur/enhance data in addition to sliders/crop/HDR. No model rerun is required
to reopen saved mask coverage. The first selection overlay previews the returned mask; combined/refined masks
remove that overlay rather than display stale coverage. Exposure rendering uses the saved result.

Enhancement and blur are explicitly rendered-copy workflows. Their newly imported copies have no link to an
existing Photos asset. Merge results directly open the new catalog DNG without sending it through sensor-RAW
reimport. Opening indexed drafts also clears a prior Photos asset link, preventing an unrelated same-item save.
Use Export/system sharing to save copies. Originals, prior edits and the existing Photos save workflow remain.
Merge exposure normalization can estimate ratios from pixels when working TIFFs lack original EXIF exposure.
Sources are full-resolution file originals/working copies; merge does not bake every source's current edits.

## Evidence recorded this update

- Rust bridge built for device, simulator and Apple-silicon Mac Catalyst.
- Unsigned iOS device and iOS simulator app builds passed.
- App launched on iPhone simulator with the original procedural export/crop chart. The Masks screen was
  captured and visually inspected; yellow theme, controls, image bounds and sheet safe areas fit the phone.
- Core ML metadata inspection confirmed the denoise tensor contract without running inference.
- No automated suite, benchmark or model inference was run by the agent. Saved tests remain unexecuted.
- AI Enhancement setup, Lens Blur setup and Merge screens were also captured and visually inspected on the iPhone simulator.
  No clipping or safe-area overlap was visible. These captures are local; no screenshots are published.
- The iPhone 17 Pro's persistent app Library was backed up before update. The final signed app was installed
  and `devicectl` confirmed launch on 2026-10-20. This is delivery evidence, not a physical feature test.
- The development profile is the existing basic profile without Increased Memory Limit; large RAW/AI/merge
  behavior still needs device verification. The full signed Mac app and iPad runtime were not exercised.

Build/install/launch or a screen capture does not prove Vision selections, Core ML inference, photo merges,
Photos round trips, rendering quality, thermal/memory behavior or parity with other photo editors.

## Saved checks for the user

New Rust coverage: `Engine/ffi/tests/computational.rs` (mask persistence/restoration, invalid input,
mask combinations, merge guards and untrusted archive rejection). New Swift coverage:
`iLightCraftTests/ComputationalToolsTests.swift` (coverage orientation/inversion, index search/serialization,
invalid vector handling and model pins). Rebuild the framework before running native integration tests.

```sh
cd Engine
cargo test --locked -p ilightcraft-ffi --test computational
cd ..
scripts/test-app.sh
```

Device acceptance on disposable media:

- [ ] Subject/person/object selection, dark/low-contrast/empty images; invert/combine/refine; exposure/undo/redo.
- [ ] Reopen/relaunch and export saved masks/removal; compare orientation after crop/rotation/flips.
- [ ] Download each optional model, interrupt/cancel, verify offline reuse, removal and corrupt-cache recovery.
- [ ] RGB denoise and 2× output dimensions, fine detail, tile seams, color, SDR-only refusal and memory failure.
- [ ] Depth inference, near/far focus, range/strength, edge artifacts, output TIFF precision and HDR preservation.
- [ ] Remove different areas, undo/redo, reopen/export, failed patch choice and very long strokes.
- [ ] Analyze/index/search photos with objects/text/faces; cancel and resume; clear index; no identity claims.
- [ ] HDR exposure brackets, moving subjects, missing EXIF, panorama projections and HDR panorama grouping.
- [ ] Merge source preservation, unique result names, cancel/background, insufficient memory and full disk.
- [ ] Original hashes unchanged; new copies cannot overwrite an unrelated Photos asset.
- [ ] iPhone/iPad touch/Pencil/VoiceOver/Dynamic Type and signed Mac runtime checks.

## Revision history

- 2026-10-20: First native Priority 4 implementation, model policy, saved checks and bounded evidence.

- 2026-10-20: Added native per-mask color controls; see [color adjustment evidence](mask-color.md). Selection/render/output acceptance remains pending.
