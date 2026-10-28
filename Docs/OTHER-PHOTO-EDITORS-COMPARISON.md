# Feature comparison with other photo editors

Last updated: 2026-10-28

This is a working checklist for comparing iLightCraft with other photo editors. It records native
app coverage, not a claim that all implementations have equivalent quality or camera support.
“Implemented” means a workflow exists; device acceptance may still be pending. Detailed status and
user decisions are in [missing features](MISSING-FEATURES.md) and [next steps](NEXT-STEPS.md).

| Area | Features to compare | iLightCraft status |
|---|---|---|
| Import and library | Files and photo-library access; RAW, HEIC and other formats; browsing | Files and Photos workflows exist; camera coverage and full device round trips need verification. |
| Editing | Exposure, color, tone curves, color mixer, grading, profiles, undo and before/after | Native controls exist; output, persistence and device acceptance vary by feature. Camera calibration remains incomplete. |
| Crop and geometry | Crop, straighten, rotate, perspective and lens corrections | Crop is implemented and generally accepted. Geometry and optics are partial; coverage needs verification. |
| Local adjustments | Brush and gradient masks, color/luminance ranges, combinations and refinement | Native workflows exist; additional mask types and input refinements remain. |
| Remove and repair | Healing, cloning, content-aware and generative removal | Healing and content-aware workflows exist; generative and automated removal remain. |
| Presets and batch | Save and apply presets, copy edits, batch processing | Native workflows exist; detailed device and persistence acceptance remains. |
| Versions and history | Edit history, saved versions, comparisons and recovery | Native workflows exist; persistence and output acceptance remain. |
| HDR and export | Extended-range display, HDR export, formats, color spaces, metadata and watermark | Implemented workflows exist; real-device HDR and output checks remain. |
| Organization and search | Albums, stacks, ratings, filters, metadata search and culling | Some native features exist; broader organization and search were skipped by user request. |
| Sync and backup | Portable backup, cross-device sync and conflict recovery | Portable backup/restore is implemented; private CloudKit sync is deferred. |
| AI tools | Subject and people masks, denoise, enhancement and depth blur | Initial on-device workflows exist; model quality and device acceptance remain. |
| Merge | HDR brackets, panoramas, alignment and deghosting | Initial workflows exist; real-source and output acceptance remain. |
| Specialized workflows | Video, tethering, maps, print and publishing | Future work; see the [feature priorities](Plans/feature-priorities.md). |
| Automation | MCP access to the active editor | Planned; not implemented. |

Use the [prioritized feature list](Plans/feature-priorities.md) for scope and acceptance criteria.
