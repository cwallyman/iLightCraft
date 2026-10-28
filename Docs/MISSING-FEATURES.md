# Missing native features — 2026-10-20

This list describes the native iPhone/iPad/Mac app, based on NEXT-STEPS and the Priority 4
implementation record. Engine support alone does not mean a native workflow is complete.

## Requested queue and implementation status

1. **Point Color — implemented, acceptance pending:** sample on the main photo; hue/saturation/luminance shifts and range controls; up to eight samples.
2. **Color grading — implemented, acceptance pending:** shadows/midtones/highlights/global wheels and blending/balance.
3. **Optics and perspective — partial native workflow:** embedded lens correction detection, manual distortion/vignette, chromatic aberration/defringe, Upright and main-photo guided perspective. External lens profile catalog and camera/lens coverage remain.
4. **Manual masks — partial native workflow:** brush, linear/radial, color/luminance ranges, feather/flow/density, add/subtract/intersect, saved coverage and local tone/detail controls. Pencil uses ordinary drawing coordinates; pressure-sensitive refinements remain.
5. **Healing and cloning — implemented controls, acceptance pending:** Remove/Heal/Clone, explicit/automatic source, feather/opacity, saved repair selection/update/delete.
6. **Presets and batch edits — implemented, acceptance pending:** create/favorite/apply, native `.lcpreset` import/export, selective copy/paste and batches of up to 20 other imported photos. Batch undo/redo lasts until the panel closes; per-photo history persists. Batch edits do not write back to Photos assets.
7. **Versions and history — implemented, acceptance pending:** named save/restore/rename/delete, alternate local edit copies, persistent history and a main-photo reference comparison.
8. **SKIPPED by user (2026-10-20) — Library organization:** albums/collections, smart collections, stacks, ratings, flags and labels. Editable local photo keywords were subsequently requested and added with the top toolbar on 2026-10-26; hands-on acceptance remains pending.
9. **SKIPPED by user (2026-10-20) — Search/culling and metadata:** metadata filters, saved searches, multi-select comparison, captions/copyright/IPTC/GPS/capture-time editing and sidecar interchange.
10. **Backup/restore implemented; CloudKit deferred by user:** Settings can copy a portable library package with checksums and stage verified recovery into a separate library for the next launch. Current library retained; device-specific Photos links excluded. CloudKit signing, sync and conflict recovery remain for later.

## Remaining parts of existing advanced tools

- **Masks:** landscape/additional body-part/depth masks, general object prompts, recomputation/status and adaptive presets. Sky, separate people and per-person skin masks already have an implementation.
- **AI enhancement:** sensor-domain denoise and Raw Details; broader input coverage. Current denoise/2× tools create SDR copies.
- **Lens Blur:** editable depth/blur layers, bokeh shapes, depth visualization and painted depth refinement. Current workflow renders a TIFF copy.
- **Removal:** generative fill, reflection removal and automatic distraction/background-person detection.
- **Intelligent library:** identified face clusters, a joint image/text content-search model and a scalable whole-library index. Current labels/OCR/face counts and imported-photo search are a first pass.
- **Merge:** source-group/result workflow refinements; real bracket/panorama quality and large-file acceptance remain.
- **Profiles:** camera-specific calibrated profiles and per-camera color verification. HSL, curves and 22 built-in creative looks are implemented.

## Later roadmap

Video/Live Photos; camera tethering; maps/geotagging; soft proofing/print/books/slideshows;
publishing and external-editor/extensions; optional hosted galleries/collaboration; guided learning.
Intel Mac support and App Store/TestFlight release packaging are not complete.

- **MCP integration — planned:** explore a local server for Mac Catalyst that can inspect and operate
  the active native editor session, with explicit access controls, safe command handling and clear
  error reporting. Assess iPhone/iPad support separately. The upstream LightCraft MCP server does
  not currently control iLightCraft, and this feature has not been implemented.

## Implemented, but acceptance still pending

RAW/HDR camera coverage, Photos save-on-Back/reopen/conflicts, HSL/profile/curve persistence and
output, real AI/mask/merge quality, large-file memory, accessibility and physical device layouts.
These are verification gaps, not wholly missing features. HEIC and general export/crop milestones
have received user acceptance; their detailed edge cases remain listed in NEXT-STEPS.

Sources: [next steps](NEXT-STEPS.md), [roadmap](Plans/feature-priorities.md),
[advanced-tool status](Verification/priority4-on-device.md), [HSL/profiles](Verification/hsl-profiles.md).

See [implementation and delivery evidence](Verification/remaining-features.md). These are first native workflows, not a parity claim.
