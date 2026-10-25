# iLightCraft feature priorities

Last updated: 2026-10-20. Scope: the native SwiftUI/Metal app on iPad, iPhone and Mac Catalyst.
This is the implementation queue for the Lightroom comparison, not the vendored engine's feature checklist.
An engine capability counts as delivered only after the native workflow is usable and verified.

Start with [the current next steps](../NEXT-STEPS.md); implementation history is in
[the changelog](../../CHANGELOG.md). Reliability fixes and device acceptance come before P2 tools.

## Priority 0: HEIC first

1. [x] **U0.1 HEIC/HEIF import and editing.** Decoder enabled and update installed; user confirmed
  "everything looks good" before requesting U1.1/U1.2. Saved extended checks remain available.
  Enable the existing pure-Rust still-image decoder
  in every app engine build. Verify Files and Photos resource import, rendered pixels, container
  orientation, color profiles, adjustment, reopen and an actionable error for corrupt/unsupported files.
  Preserve original bytes. Record simulator, Mac and physical-device evidence separately.
  HEIC export, gain-map HDR and Live Photos are separate tasks below.

## Priority 1: finish the everyday photo workflow

2. [x] **U1.1 Export and share (installed; user confirmed all good).** Native export through the shared Rust encoder; JPEG, PNG and TIFF,
   format/quality/size/color-space controls, metadata choices, output sharpening, watermark and batch
   export. Verify a saved file in another decoder and cancellation/full-disk failures.
3. [x] **U1.2 Crop and straighten (installed; user confirmed all good).** Crop handles, aspect-ratio presets, rotate/flip and straighten;
   normalized settings, undo/redo, persisted edits and matching preview/export.
4. [ ] **U1.3 Reliable RAW and HDR workflow (implemented and installed on iPhone; physical camera/HDR checks pending).** Actual camera-file coverage and clear unsupported-file
   errors; calibrated color, HDR input, extended-range native display and HDR export including HEIC
   where supported. Verify memory behavior with large files. Do not equate Metal with HDR support.
5. [ ] **U1.4 Apple Photos save and reopen (Photos save callback crash corrected and installed on iPhone; round-trip/conflict checks pending).** Save a non-destructive adjustment to the same asset,
   original preservation, external-edit conflict detection/recovery and explicit library choice.

## Priority 2: core editing tools

6. [ ] **U2.1 Tone curves (implemented and installed; acceptance pending).** RGB and individual-channel curves with points, reset and undo. Native graph, point selection/deletion, Input/Output sliders, per-channel/all-channel resets and curve-inclusive undo snapshots are available. See [verification](../Verification/tone-curves.md).
7. [ ] **U2.2 Advanced color (partial).** Native eight-band HSL mixer and built-in creative profiles with Amount/favorites/search are implemented. Point Color, color-grading wheels and camera-specific calibration remain. Hands-on acceptance is pending; see [verification](../Verification/hsl-profiles.md).
   Include profile selection and verify color-managed output.
8. [ ] **U2.3 Optics and geometry.** Lens-profile selection/automatic matching, distortion correction,
   chromatic-aberration removal, defringing, perspective controls and Upright.
9. [ ] **U2.4 Manual local adjustments.** Brush, linear/radial gradients, color/luminance range masks,
   mask add/subtract/intersect, feathering and Pencil pressure/hover behavior.
10. [ ] **U2.5 Healing and cloning.** Spots, brush selection, source choice, remove/restore and undo;
   clear progress and cancellation for slower operations.
11. [ ] **U2.6 Presets and batch edits.** Save/apply/import presets, favorites, copy/paste selected
    adjustments and multi-photo application. Adaptive presets depend on U4.1.
12. [ ] **U2.7 Versions and history.** Named versions/snapshots, alternate copies, persistent browsable
    history, compare/reference views for different photos and restoration after relaunch.

## Priority 3: library and multi-device use

13. [ ] **U3.1 Organization.** App-managed albums/collections, smart albums, stacks, ratings,
    pick/reject flags, color labels and keyword editing. Preserve existing Apple Photos album browsing.
14. [ ] **U3.2 Search and culling.** Metadata filters, saved searches, fast multi-photo selection,
    side-by-side comparison and assisted culling. Semantic search/face recognition depend on U4.5.
15. [ ] **U3.3 Metadata.** Read/edit captions, copyright, keywords and supported IPTC/GPS fields;
    sidecar/interchange policy, capture-time editing and original preservation.
16. [ ] **U3.4 Device sync.** Migrate optional private CloudKit sync, originals and complete edits;
    albums, versions, offline recovery, conflict resolution and account changes. Verify two devices.
17. [ ] **U3.5 Backup and migration.** Native library backup/restore and supported Lightroom
    catalog/settings import, with explicit reporting of settings/looks that cannot transfer.

## Priority 4: computational photography and AI

18. [ ] **U4.1 Semantic masks.** Subject, sky, background, objects, people/body parts, landscape and
    depth masks; refinement and AI-mask recomputation/status. Then adaptive profiles/presets.
    **Partial implementation (2026-10-20):** Subject/background/people and tap-selected objects now use local Vision masks, with exposure, combinations, inversion, edge refinement and saved undo state. Sky/landscape/body-part/depth selections, adaptive presets and recomputation remain.

19. [ ] **U4.2 AI enhancement.** Shippable, permissively licensed models for AI Denoise, Raw Details
    and Super Resolution; supported sensor/file types, model setup, progress and cancellation.
    **Partial implementation (2026-10-20):** Optional pinned BSD-3-Clause Core ML RGB denoise and 2× Super Resolution now create separate SDR PNGs. Sensor-domain AI denoise and Raw Details remain. Real-device inference/quality acceptance is pending.

20. [ ] **U4.3 Lens Blur.** Depth estimation, focus range, blur/bokeh controls and depth refinement.
    **Partial implementation (2026-10-20):** Optional pinned Apache-2.0 local depth model, relative focus/range and blur-to-float-TIFF copy now exist. Editable depth, bokeh shapes and refinement remain; model runtime acceptance is pending.

21. [ ] **U4.4 Advanced removal.** Content-aware and generative removal, object/distraction detection,
    reflection removal and background-people removal. Service/model decisions belong to this task.
    **Partial implementation (2026-10-20):** Native brush-based content-aware patch healing now persists with edits and undo. Generative, reflection and automatic background-people/distraction removal remain.

22. [ ] **U4.5 Intelligent library.** Face recognition and natural-language/content-based photo search,
    with an explicit on-device/model-download policy.
    **Partial implementation (2026-10-20):** Local image labels, OCR, face counts and imported-library indexing/search now exist, including English label/text embeddings when available. Face identities and joint image-text search remain.

23. [ ] **U4.6 Photo merge.** HDR brackets, panorama and HDR panorama; alignment, deghosting,
    projection/crop options, memory limits and reusable non-destructive results.
    **Partial implementation (2026-10-20):** Native ordered-source HDR/panorama/HDR-panorama controls now use cancellable engine jobs, deghost/projection/crop options, memory guards and new DNG output. Real bracket/panorama output acceptance remains.

## Priority 5: sharing, media and specialist workflows

24. [ ] **U5.1 Hosted sharing and web access.** Shared album links, invitations, collaboration,
    comments/likes, web viewing/editing and notifications. Requires a separate service design.
25. [ ] **U5.2 Video and Live Photos.** Video import/playback, trim, color adjustments and export;
    explicitly design how paired Live Photo resources are preserved.
26. [ ] **U5.3 Tethered capture.** Supported cameras, connection recovery, watched folders and import presets.
27. [ ] **U5.4 Map tools.** Interactive map, drag-to-geotag and saved locations.
28. [ ] **U5.5 Print and presentation.** Soft proofing, print layouts/direct printing, book layouts and
    advanced slideshows including music, titles and export.
29. [ ] **U5.6 Publishing and extensions.** Managed publishing queues, web galleries, external-editor
    round trips and a documented export/publish/metadata extension interface.
30. [ ] **U5.7 Learning and community.** Guided tool help/tutorials, community edits and recommended
    presets, if a hosted community becomes part of the product.

## Delivery requirements

At the user's request, save automated tests and benchmarks for manual use; do not run them automatically.
Every user-facing task needs meaningful regression coverage, an actual app run and visual review,
plus import/edit/export/reopen checks where relevant. Distinguish build, automated, simulator,
Mac and physical-device evidence. Accessibility, touch/Pencil use, responsiveness, safe areas,
original preservation and actionable errors apply throughout. Never mark a task complete from
an engine API or build result alone. No promises of Lightroom-identical rendering without measurement.

The current HEIC evidence and outstanding checks are recorded in `../Verification/heic-support.md`.
Export/crop evidence and the saved tests are in `../Verification/export-and-crop.md`.
RAW/HDR/Photos evidence and user checks are in `../Verification/raw-hdr-photos.md`.

## Revision history

- 2026-10-20: User moved Priority 4 ahead of Priority 2. Counted HEIC as item 1 so U4.1–U4.6 are items 18–23. Added partial implementation notes; no Priority 4 row is marked complete. On-device processing chosen; hosted sharing remains separate.

- 2026-10-20: Added native U2.1 Tone Curves; kept the row unchecked pending hands-on persistence, output and Photos acceptance.

- 2026-10-20: Exposed HSL and built-in profiles in native U2.2 panels; remaining color tools and real-output acceptance stay unchecked.

## Remaining-feature update — 2026-10-20

Native first passes for missing-feature queue 1–7 and portable backup/restore are implemented. Items 8 and 9 remain skipped. CloudKit is deferred by user. See [missing-feature status](../MISSING-FEATURES.md) and its verification record for limits and acceptance work.
