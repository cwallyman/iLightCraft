# Camera tone fix: posterized shadows

Date: 2026-10-11. Second change to `Engine/crates` (see `Engine/CHANGES.md`).

## Cause

`fit_tone` (`Engine/crates/engine/src/camera_preview.rs`) fits the camera's tone curve to the embedded JPEG with
32 median knots and pools falling neighbours (isotonic regression). Every knot of a pooled block got the same
output, so the curve had flat runs. On the X-T4 RAF, scene luminance 0.0139 to 0.0196 became one display level
(sRGB code 43/44): the dark foliage. A 16-bit render showed the same plateau, drafts matched full renders byte for
byte, and the canvas added nothing.

## Fix

Each pooled block becomes one knot at its mean input, the other knots are placed on the line through those
points, and two passes move each knot halfway toward the line between its neighbours. The curve never falls and
rises wherever the data rises. `RENDER_CACHE_VERSION` went from 16 to 17 so cached renders are redone.

## Shadow histogram spike

Largest bin over its neighbours, sRGB luma codes 8 to 100, neutral render at 2048 px. Reference: Core Image
`CIRAWFilter` at the same size.

| RAW | Before | After | Core Image |
|---|---|---|---|
| X-T4 RAF | 7.5 | 1.4 | 1.2 |
| Z 7 NEF | 3.9 | 3.1 | 2.4 |
| A7 IV ARW | 2.6 | 1.9 | 1.4 |
| R5 CR3 | 4.6 | 2.8 | 2.2 |
| iPhone DNG | 1.3 | 1.3 (byte-identical) | 1.1 |

On the iPad (Release, lossless screenshots of the RAF): 5.1 before, 1.3 after; during an exposure sweep 5.6 to 12.4
before, 1.4 to 2.2 after.

## Goldens

Regenerated on the Mac and exported on the iPad with the fix. Mac against iPad: 25 of 25 pairs, mean and p99
ΔE2000 0.0000, as before (`equivalence.md`). The look change against the v0 goldens is intended: mean ΔE 0.35 to 0.56
on the RAF (p99 up to 3.4, where the plateau was), 0.42 to 0.64 on the NEF, 0.32 to 0.44 on the ARW, 0.34 to 0.41 on
the CR3, and 0 on the DNG. `stage_bench` and open times are unchanged within noise (measured against the parent
commit; `stage_bench` does not exist at the v0 baseline).
