# Changes to the vendored engine

Files under `crates/` that differ from upstream (see `UPSTREAM.md` for the commit), as Apache-2.0
section 4(b) requires. Each changed file also carries a notice at its top.

| Date | File | What | Why |
|---|---|---|---|
| 2026-10-19 | `crates/develop/src/settings.rs`, `crates/pipeline/src/output.rs`, `crates/pipeline/src/finish.rs`, `crates/pipeline/src/tone.rs` | Backported bounded HDR tone/gamut handling and extended linear float output from the local upstream reference; added optional HDR settings while retaining the SDR path. | Native EDR display and HDR export must retain highlights above SDR white. Performance measurements and saved HDR tests are deferred at the user's request. |
| 2026-10-09 | `crates/gpu/src/ctx.rs` | `Gpu::upload` writes uploads under 1 MiB into a buffer from the free pool (`buffer(len)` plus `queue.write_buffer`) instead of always creating a new one. Larger uploads, usage flags and labels are unchanged. | Each preview uploads a 32 KiB LUT block. The new buffer joined the free pool on drop and was never reused, so the pool grew by one buffer per frame up to its limit (about 317 MiB and +3 MiB/s of footprint on the iPad once resident stages removed the per-frame source upload). |
| 2026-10-11 | `crates/engine/src/camera_preview.rs` | `fit_tone` no longer gives every knot of a pooled block (pool adjacent violators) the pooled value. Each block becomes one point at its knots' mean input, every knot takes its value on the line through those points (from the origin, extended past the last point, kept below 1), then two passes move each knot halfway to the chord of its neighbours. The curve stays non-decreasing and rises wherever the data does. Test `a_pooled_tie_leaves_no_flat_run_in_the_tone_curve`. | A pooled block was a flat segment of the camera tone curve, a plateau: on the X-T4 RAF, scene luminance 0.0139 to 0.0196 (dark foliage) all came out at one display value, flat patches with hard edges (a luminance histogram spike of 7.5x its neighbours). The Z 7 NEF and the A7 IV ARW had flat runs too. |
| 2026-10-11 | `crates/engine/src/media.rs` | `RENDER_CACHE_VERSION` 16 to 17. | The camera tone fix changes the pipeline's output; upstream's rule for this constant invalidates the cached thumbnails rendered with the old curve. |

| 2026-10-20 | `crates/engine/src/cmd/color.rs`, `crates/engine/src/tests_color.rs` | Added optional `pointColor.pick` uncropped-preview coordinate mode, with saved crop reset only in a render copy. | Main-photo sampling must target the tapped rendered pixel after geometry, including outside an existing crop. Existing source-coordinate callers retain their behavior. Regression saved, unrun by request. |

| 2026-10-20 | `crates/engine/src/cmd/masks.rs` | Optional uncropped, pre-perspective preview coordinates for color-range samples. | Native manual masks must sample the pixel shown in the main-photo mask stage. |
| 2026-10-20 | `crates/engine/src/cmd/develop.rs` | Bounded, validated atomic `develop.restoreBatch` command. | Native other-photo batch undo/redo restores settings without changing source files. |

| 2026-10-26 | `crates/inpaint/*`, `crates/pipeline/src/spots.rs`, `crates/pipeline/Cargo.toml`, `crates/develop/src/settings.rs`, `crates/engine/src/cmd/masks.rs`, manifest/lock and NOTICE | Focused backport of pure-Rust deterministic Content-Aware Fill, its spot mode and bounded-radius handling. No broad engine upgrade. | Actual non-destructive fill in native Masking and Remove. Upstream synthetic regressions retained; tests and performance benchmarks deferred by user request. |

| 2026-10-26 | `ffi/src/native_commands.rs` | Optional validated overlay mode, RGB color and opacity on the native crop preview query. | Masking overlay controls match LightCraft without changing saved edits. |

| 2026-10-26 | `ffi/src/native_commands.rs`, `ffi/src/session.rs` | Read-only selected-mask pin query using geometric anchors or the centroid of bounded stored foreground logits. | Show Pins uses actual mask data without rerunning selection models. |

| 2026-10-26 | `ffi/src/native_commands.rs`, `ffi/src/session.rs` | Bounded read-only `ilightcraft.comparisonPreview` using the engine before/after render job with current crop. | Native same-photo side-by-side comparison without changing settings or selection. |
