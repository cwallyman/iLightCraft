# Memory and energy map (E0)

Where the app's memory and per-frame cost go today, on the iPad, for the 26 MP RAF (`DSCF0267.RAF`, 6240 x 4160) and the
46 MP NEF (`Z7-14bit-lossless-L.NEF`, 8256 x 5504). Measurement only: no product behaviour changed. It is the baseline for
E1 to E5 of the M6 spec. Raw logs and CSVs: `.superpowers/sdd/2026-10-12-m6/e0-measurements/` (`raw-logs/`, `memory-map.csv`,
`cost.csv`, `analyze.py`).

## Setup

| Item | Value |
|---|---|
| Device | iPad Air 11-inch (M2), `iPad14,8`, 8 GB, iPadOS 27.0, cabled, `-UnveilEngineDir fresh` unless stated. Thermal state `nominal` in every memory-map, cost and sampler record |
| Build | Release, branch `elio/memory-map` from `main` (885e14f) plus the diagnostics below, engine built with `scripts/build-xcframework.sh` (default CPU, as the earlier baselines) |
| Free space (`-UnveilRun disk`) | before the runs 62 259 200 000 bytes available (72 475 001 065 important), read from the console of the first launch and not archived; after all runs and the device test suite 62 259 200 000 (72 585 945 697 important), archived in `raw-logs/disk-after.log` |
| Instruments | none (worker rules). Everything below is counters printed by the app and read from the console |

### What was added (diagnostics only)

- Engine bridge (`Engine/ffi/src/diagnostics.rs`, read only): the file hooks (decode, import probe, embedded preview) are wrapped
  so each call is logged with wall time and calling-thread CPU time (`unveil.loads`, a ring of the newest 512 events); the render
  thread and the engine thread time each render, window histogram frame and frame delivery per category (`unveil.renders`);
  `library.memory` also answers what the preview and window stages hold, on the host and on the device (`unveil`). All timers
  and the log sit behind one flag that is off in every normal launch and is set only by the app's measurement options
  (`unveil.diagnostics {"enabled": true}`): off, a render reads no clock and the hooks add one atomic read. Tests:
  `Engine/ffi/tests/diagnostics.rs` (off until enabled, then counted, then off again) and the ring and inert-span unit tests.
- App: launch options `-UnveilMemoryMap`, `-UnveilTimeline`, `-UnveilCost`, `-UnveilSweepFull`, and `-UnveilRun metal`
  (a calibration of what a shared Metal buffer and a malloc block cost the footprint, and whether a large block can be given
  back). Probes: `MemoryMapReport` (task_vm_info, `malloc_zone_statistics`, `MTLDevice.currentAllocatedSize`, the address space
  by VM tag), `ProcessCostProbe` (getrusage, per-thread CPU, `task_power_info_v2`), `OpenTimeline`, `CanvasGPUTime`,
  `SliderLatencyLog`. Each records only while a measurement option asks and costs one atomic read otherwise (no clock, no lock).
  The measurement runs live in `EditorLaunchRunner+Measurements.swift`.

## Method

- **Moments.** After the open's first full frame: `open` (immediately), `fit` (15 s hold at fit), `zoom-100` (zoom to 100 %,
  wait for the first full window, 10 s hold), `fit-after-10s` (zoom out, 10 s; the window release fires 2 s after the zoom out),
  and a fourth point at 30 s (in the CSV). Three runs per RAW, each from a new process with a fresh library.
- **Owners.** Engine counters (`library.memory`: decoded sources, render cache, GPU buffers allocated / pooled / retired; the
  bridge's stage sizes), `FrameSink` buffer sizes, `MTLDevice.currentAllocatedSize`, and `phys_footprint`. "Named by counters" is
  the engine's CPU caches plus all engine GPU buffers; the remainder is `phys_footprint` minus that.
- **How GPU bytes count.** `-UnveilRun metal` (raw-logs/calibrate-metal.log): a 256 MiB shared `MTLBuffer` costs the footprint 0
  until it is written, then 256 MiB; a 256 MiB malloc block likewise, and after `free` plus `malloc_zone_pressure_relief` it still
  counts (`MALLOC_LARGE` stays dirty, 573 MiB at +1 s), and the next same-size allocation reuses it without growing the
  footprint. Giving it back works with `munmap` (829 to 573 MiB at once) and with `madvise(MADV_FREE_REUSABLE)` (573 to 317 MiB
  at once); `raw-logs/calibrate-metal-2.log`. The app with no photo is 72 to 82 MiB.
- **Open timeline.** Marks on one clock (`CLOCK_UPTIME_RAW`) from the app (open, copy, hash, each engine command, preview request,
  frame delivered, first frame presented) merged with the engine's own load events. Cold = fresh engine library, warm = the
  default library that already knows the photo (as the earlier baselines). Each launch is a new process, so no decoded source is
  cached in either. A run that also took the memory map made one extra `library.memory` read after the first frame.
- **Per-frame cost.** 30 s exposure sweeps (60 Hz drag, release once a second), `-UnveilCost`, after a 3 s settle (and the first
  full window for 100 %). CPU: `getrusage` total plus per-thread `thread_info` deltas; render-thread and engine-thread CPU per
  render from `CLOCK_THREAD_CPUTIME_ID` inside the bridge; canvas GPU time from each canvas command buffer's
  `gpuEndTime - gpuStartTime`; energy from `task_power_info_v2.task_energy`; `SliderToFrame` from the app's own interval (request
  to the presented handler, the same instants as the signpost). Three runs per configuration, median and (min to max).
- **Frames.** A frame is a frame the engine delivered (sum of the delivery counts). The sweep drags at 60 Hz but only one render
  runs at a time and the newest request wins, so about 31 frames per second reach the screen in the drag configurations.

## 1. Memory by owner

The footprint is not a sum of the engine's counters. Two things dominate what is left over: memory the allocator keeps after
free (not returned until much later or never; it differs run to run) and the duplicated full-size source at 100 %.

#### RAF 26 MP: memory by owner, MiB, median (min to max) of 3 runs

| Owner | open | fit | zoom-100 | fit-after-10s |
|---|---|---|---|---|
| footprint | 667 (664 to 668) | 577 (488 to 579) | 1853 (1792 to 2013) | 642 (642 to 1065) |
| lifetime peak | 702 (696 to 702) | 702 (696 to 702) | 2339 (2323 to 2339) | 2339 (2323 to 2339) |
| decoded original (CPU f32) | 0 (0 to 0) | 0 (0 to 0) | 297 (297 to 297) | 297 (297 to 297) |
| preview-level source (CPU f32) | 33 (33 to 33) | 33 (33 to 33) | 33 (33 to 33) | 33 (33 to 33) |
| thumbnail sources + render cache (CPU) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |
| stages host copies (CPU) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |
| preview stages (GPU: uploaded source + derived) | 146 (146 to 146) | 146 (146 to 146) | 146 (146 to 146) | 146 (146 to 146) |
| window stages (GPU) | 0 (0 to 0) | 0 (0 to 0) | 126 (126 to 126) | 0 (0 to 0) |
| GPU source copy of the original (derived) | 0 (0 to 0) | 0 (0 to 0) | 297 (297 to 297) | 0 (0 to 0) |
| GPU pool, pooled | 184 (184 to 184) | 184 (184 to 184) | 304 (304 to 304) | 0 (0 to 0) |
| GPU pool, retired | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |
| engine GPU buffers total | 330 (330 to 330) | 330 (330 to 330) | 874 (874 to 874) | 146 (146 to 146) |
| named by counters (CPU + GPU) | 363 (363 to 363) | 363 (363 to 363) | 1204 (1204 to 1204) | 476 (476 to 476) |
| remainder (footprint - named) | 303 (301 to 304) | 213 (125 to 216) | 649 (589 to 809) | 166 (166 to 588) |
| heap in use (all malloc zones) | 79 (79 to 79) | 78 (78 to 78) | 376 (376 to 376) | 376 (376 to 376) |
| other heap in use (heap - CPU named) | 46 (46 to 46) | 45 (45 to 45) | 46 (46 to 46) | 45 (45 to 46) |
| FrameSink buffers (reserved) | 75 (75 to 75) | 75 (75 to 75) | 75 (75 to 75) | 75 (75 to 75) |
| Metal allocated (device) | 477 (477 to 477) | 445 (445 to 445) | 1003 (1003 to 1003) | 276 (276 to 276) |
| Metal other (device - engine GPU - sink) | 71 (71 to 71) | 39 (39 to 39) | 55 (55 to 55) | 55 (55 to 55) |
| internal | 250 (250 to 264) | 210 (122 to 213) | 917 (858 to 1077) | 436 (436 to 858) |
| compressed | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |

#### NEF 46 MP: memory by owner, MiB, median (min to max) of 3 runs

| Owner | open | fit | zoom-100 | fit-after-10s |
|---|---|---|---|---|
| footprint | 865 (854 to 866) | 746 (511 to 824) | 2488 (1863 to 2700) | 1081 (915 to 1750) |
| lifetime peak | 929 (918 to 945) | 929 (918 to 945) | 3825 (3786 to 3827) | 3825 (3786 to 3827) |
| decoded original (CPU f32) | 0 (0 to 0) | 0 (0 to 0) | 520 (520 to 520) | 520 (520 to 520) |
| preview-level source (CPU f32) | 50 (50 to 50) | 50 (50 to 50) | 50 (50 to 50) | 50 (50 to 50) |
| thumbnail sources + render cache (CPU) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |
| stages host copies (CPU) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |
| preview stages (GPU: uploaded source + derived) | 163 (163 to 163) | 163 (163 to 163) | 163 (163 to 163) | 163 (163 to 163) |
| window stages (GPU) | 0 (0 to 0) | 0 (0 to 0) | 126 (126 to 126) | 0 (0 to 0) |
| GPU source copy of the original (derived) | 0 (0 to 0) | 0 (0 to 0) | 520 (520 to 520) | 0 (0 to 0) |
| GPU pool, pooled | 184 (184 to 184) | 184 (184 to 184) | 304 (304 to 304) | 0 (0 to 0) |
| GPU pool, retired | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) | 0 (0 to 0) |
| engine GPU buffers total | 348 (348 to 348) | 348 (348 to 348) | 1114 (1114 to 1114) | 163 (163 to 163) |
| named by counters (CPU + GPU) | 398 (398 to 398) | 398 (398 to 398) | 1684 (1684 to 1684) | 733 (733 to 733) |
| remainder (footprint - named) | 467 (456 to 468) | 348 (113 to 426) | 804 (179 to 1016) | 347 (181 to 1016) |
| heap in use (all malloc zones) | 84 (84 to 84) | 83 (83 to 83) | 603 (603 to 603) | 603 (603 to 603) |
| other heap in use (heap - CPU named) | 34 (34 to 34) | 33 (33 to 33) | 33 (33 to 33) | 33 (33 to 33) |
| FrameSink buffers (reserved) | 75 (75 to 75) | 75 (75 to 75) | 75 (75 to 75) | 75 (75 to 75) |
| Metal allocated (device) | 486 (486 to 494) | 462 (462 to 462) | 1243 (1243 to 1243) | 293 (293 to 293) |
| Metal other (device - engine GPU - sink) | 63 (63 to 71) | 39 (39 to 39) | 55 (55 to 55) | 55 (55 to 55) |
| internal | 441 (441 to 442) | 362 (127 to 440) | 1093 (561 to 1522) | 746 (562 to 1522) |
| compressed | 0 (0 to 0) | 0 (0 to 0) | 116 (0 to 205) | 97 (0 to 115) |


### Where the footprint is, by VM tag

`phys_footprint` splits into the CPU side (`internal`, which the VM regions show as MALLOC_LARGE, MALLOC_SMALL and tag 100),
the compressed memory, and a graphics side that the VM regions do not list. The graphics side equals the engine's GPU buffers
plus "Metal other" (drawables, small textures) in every run: the difference column is -4 to +22 MiB, and it is the same with
the pool full (fit, 184 MiB pooled), with the pool at 304 MiB (100 %) and with the pool trimmed to 0 (after the zoom out).
So **every pooled GPU byte is charged to the footprint** (the buffers were written by the GPU, which is what the calibration
says matters), the 330 MiB of engine GPU buffers at fit are all real, and a pool trim returns its full size. Tag 100 is the
shared buffers the CPU wrote: 37 MiB at fit and 63 at 100 % are consistent with the FrameSink frames (about 2.5 frames of 14.8 MB, then
the window frames); not separately proven. IOSurface regions (90 to 121 MiB dirty) are the sink's reserved buffers and the drawables and are not
charged to the footprint.

#### RAF 26 MP: footprint split by VM tag, MiB, per run (r1 / r2 / r3)

| Moment | footprint | internal (CPU side) | of it MALLOC_LARGE dirty | MALLOC_SMALL | tag 100 | other internal | compressed | graphics side = footprint - internal - compressed | engine GPU buffers + Metal other | difference |
|---|---|---|---|---|---|---|---|---|---|---|
| open | 664 / 667 / 668 | 250 / 250 / 264 | 170 / 170 / 170 | 37 / 36 / 37 | 37 / 40 / 41 | 6 / 3 / 16 | 0 / 0 / 0 | 415 / 417 / 404 | 402 / 402 / 402 | +13 / +15 / +2 |
| fit | 577 / 488 / 579 | 210 / 122 / 213 | 170 / 51 / 137 | 37 / 29 / 33 | 37 / 39 / 37 | -34 / 3 / 5 | 0 / 0 / 0 | 366 / 366 / 366 | 370 / 370 / 370 | -3 / -4 / -3 |
| zoom-100 | 1853 / 1792 / 2013 | 917 / 858 / 1077 | 822 / 771 / 980 | 36 / 30 / 38 | 63 / 65 / 63 | -5 / -7 / -5 | 0 / 0 / 0 | 936 / 934 / 936 | 928 / 928 / 928 | +8 / +6 / +8 |
| fit-after-10s | 642 / 1065 / 642 | 436 / 858 / 436 | 348 / 771 / 348 | 29 / 30 / 29 | 63 / 65 / 63 | -5 / -7 / -5 | 0 / 0 / 0 | 206 / 207 / 206 | 201 / 201 / 201 | +5 / +6 / +5 |

#### NEF 46 MP: footprint split by VM tag, MiB, per run (r1 / r2 / r3)

| Moment | footprint | internal (CPU side) | of it MALLOC_LARGE dirty | MALLOC_SMALL | tag 100 | other internal | compressed | graphics side = footprint - internal - compressed | engine GPU buffers + Metal other | difference |
|---|---|---|---|---|---|---|---|---|---|---|
| open | 865 / 866 / 854 | 441 / 442 / 441 | 360 / 360 / 360 | 38 / 39 / 38 | 29 / 38 / 27 | 14 / 5 / 16 | 0 / 0 / 0 | 423 / 424 / 413 | 419 / 411 / 411 | +5 / +13 / +3 |
| fit | 746 / 511 / 824 | 362 / 127 / 440 | 360 / 70 / 360 | 39 / 30 / 38 | 40 / 38 / 37 | -76 / -10 / 5 | 0 / 0 / 0 | 384 / 383 / 384 | 387 / 387 / 387 | -4 / -4 / -3 |
| zoom-100 | 1863 / 2488 / 2700 | 561 / 1093 / 1522 | 499 / 892 / 935 | 161 / 284 / 538 | 62 / 62 / 62 | -161 / -145 / -12 | 116 / 205 / 0 | 1186 / 1191 / 1177 | 1168 / 1168 / 1168 | +18 / +22 / +9 |
| fit-after-10s | 915 / 1081 / 1750 | 562 / 746 / 1522 | 478 / 777 / 935 | 40 / 277 / 538 | 62 / 62 / 62 | -18 / -370 / -13 | 115 / 97 / 0 | 238 / 238 / 227 | 218 / 218 / 218 | +20 / +20 / +9 |


The dirty-page columns are not exact (a page counted dirty can be reusable or compressed, hence some "other internal" noise, left
out of the table). The CPU-side numbers to use are `internal` and MALLOC_LARGE: at fit MALLOC_LARGE is 170 MiB against 33 MiB of
named preview source, and at 100 % 771 to 980 MiB against 330 MiB of named sources and 376 MiB of heap in use.

Reading the owner table (RAF, MiB, median run unless a range is given):

- **fit.** 577 footprint = 33 preview source (CPU) + 146 preview stages (GPU) + 184 GPU pool + 213 remainder. The remainder is
  CPU-side memory the counters do not name (MALLOC_LARGE beyond the preview source, up to 137; MALLOC_SMALL 37, which holds the
  Swift and UI heap; the FrameSink frames in tag 100, 37) plus Metal other (39). The idle app with no photo is 72 to 82 of
  that. The MALLOC_LARGE part is the allocator's retention of decode temporaries and is the spread: the `fit` footprint is 488 to
  579 across the 3 runs (in the run that read 488, MALLOC_LARGE had dropped from 170 to 51 MiB between the two moments).
- **zoom-100.** The decoded original is held twice: 297 MiB on the CPU (`fullSource`) and 297 MiB on the GPU (the shared device
  copy of the original, derived as allocated - pooled - stages: it equals `fullSource` to the byte on both RAWs, 297 and 520 MiB).
  Plus window stages 126, preview stages 146, pool 304, preview source 33. The remainder, 649 (589 to 809), is mostly freed
  decode temporaries still mapped (MALLOC_LARGE 771 to 980 MiB against 376 MiB of heap in use).
- **fit-after-10s.** The window release works for the GPU: pool 304 to 0, window stages and the GPU copy of the original gone,
  Metal allocated 1003 to 276 MiB. It does not work for the CPU: the 297 MiB original stays (documented), and the footprint
  lands anywhere from 642 to 1065 MiB (RAF) and 915 to 1750 MiB (NEF) depending on whether the allocator gave back the decode
  temporaries; the 30 s moment is the same for the RAF and 890 to 1219 MiB for the NEF (the compressor and the purge act slowly).
- **Lifetime peak** (`ledger_phys_footprint_peak`): 702 MiB at the open, **2339 MiB (RAF) and 3825 MiB (NEF)** at the first
  zoom to 100 %, the transient of the full-size decode. This, not the steady value, is what jetsam sees. See section 4b for
  what is known about its composition.
- Not separable here: catalog and journal (inside MALLOC_SMALL and "other heap in use", 33 to 46 MiB above the 22 MiB idle heap
  together with the Swift/SwiftUI heap).

## 2. Open timeline

Milliseconds, median (min to max), 3 runs each (the 4 warm columns skip a priming launch that added the photo to the library).

| Phase | RAF 26 MP cold | RAF 26 MP warm | NEF 46 MP cold | NEF 46 MP warm |
|---|---|---|---|---|
| copy + hash (cold ms, in the open: hash of the file, copy skipped when the copy exists) | 17.0 (16.9 to 17.1) | 21.9 (21.5 to 22.0) | 29.1 (28.7 to 29.7) | 33.6 (33.6 to 33.6) |
|   of which hash | 16.8 (16.7 to 16.9) | 21.6 (21.3 to 21.8) | 28.8 (28.5 to 28.9) | 33.4 (33.4 to 33.4) |
| catalog import (all engine commands before the preview request) | 75.6 (23.9 to 77.1) | 4.3 (4.2 to 4.5) | 402.2 (399.8 to 403.7) | 1.0 (0.9 to 1.0) |
|   of which import probe (read + hash + header in the engine) | 65.1 (13.2 to 65.6) | 0.0 (0.0 to 0.0) | 390.7 (390.6 to 394.1) | 0.0 (0.0 to 0.0) |
| decode (calling-thread wall of the engine file loader) | 434.1 (425.0 to 441.4) | 434.5 (429.9 to 442.9) | 428.5 (427.7 to 429.7) | 436.5 (434.3 to 440.2) |
| render and delivery after the decode (decode end to frame delivered) | 73.9 (72.7 to 78.2) | 79.5 (76.3 to 80.9) | 70.2 (68.0 to 82.1) | 74.1 (71.3 to 77.6) |
| present (frame delivered to presented) | 66.4 (53.6 to 80.5) | 63.9 (59.8 to 64.7) | 83.7 (52.9 to 86.2) | 61.4 (58.8 to 65.1) |
| open total (open to first frame presented) | 676.0 (593.9 to 688.9) | 606.9 (593.9 to 615.6) | 1011.9 (997.9 to 1017.2) | 612.0 (600.5 to 615.4) |
| number of decodes up to the first frame | 1 (1 to 1) | 1 (1 to 1) | 1 (1 to 1) | 1 (1 to 1) |
| number of decodes in the 3 s after the open | 1 (1 to 1) | 1 (1 to 1) | 1 (1 to 1) | 1 (1 to 1) |

The catalog import row is the sum of the engine command durations before the preview request (the gaps between commands are
left out: import begin to preview request is 76.9 / 5.7 / 403.5 / 2.3 ms). The RAF cold import varies with the file cache: 23.9 ms
in one run (probe 13 ms, an open total of 594 ms, equal to the warm opens) and 76 to 77 ms in the other two (probe 65 ms), so the
cold median of 3 hides a bimodal value.

Cold copy of the file into an empty folder, outside the open (ms): RAF 26 MP: 61.1 (60.7 to 61.4); NEF 46 MP: 117.6 (117.3 to 126.8)


- An open decodes **once** (Preview level, 2560 px long edge, 430 ms on both RAWs, run on worker threads: the calling thread's
  CPU is 4 to 8 ms), and nothing else decodes in the 3 s after it. The first zoom to 100 % decodes again at full size
  (RAF 6240 x 4160, 908 to 935 ms; NEF 8256 x 5504, 1303 to 1348 ms) and the first full window arrives 1.03 to 1.10 s (RAF) and
  1.50 to 1.98 s (NEF) after the zoom starts. Whether a second zoom to 100 % decodes again was not measured here (each run zooms once; the engine's own note says the original stays cached).
- The decode is 64 to 72 % of the open (42 % on the NEF cold open). The NEF cold open adds a 391 ms import probe inside `library.import` (a file read, a hash and a header parse; the app's own hash
  of the same file takes 29 ms, so the probe's cost is not explained by the hash alone and the cause was not identified);
  warm skips it (the record exists). The app's own hash of the file is 17 to 34 ms, the copy into Imports is skipped
  when the copy exists (a cold copy of the file into an empty folder, outside the open, is 61 ms RAF and 118 ms NEF).
- After the decode: 70 to 80 ms to render and deliver the frame, then 53 to 87 ms until the canvas reports it presented (display
  pipeline, not reducible by the engine).

## 3. Per-frame cost

Sweep configurations: `fit, draft` is the normal drag (about 31 frames per second reach the screen, one full render a second);
`fit, 60 Hz...` requests a draft and a full render on every tick, so the frames are a mix of the two and the rate doubles (it is
not a pure full render: a drag always asks for a draft first); `100 % window, draft` is the same drag with the canvas at 100 %
(window renders, the whole-photo histogram frame every 80 ms). Pure draft and pure full render costs are in the per-category rows.

#### RAF 26 MP: per-frame cost over a 30 s sweep, median (min to max)

| Metric | fit, draft (drag, full render once a second) | fit, 60 Hz drag with a release every tick (draft and full mixed) | 100 % window, draft (drag) |
|---|---|---|---|
| frames delivered | 935 (934 to 935) | 1811 (1805 to 1869) | 956 (955 to 956) |
| frames per second | 31.15 (31.12 to 31.15) | 60.34 (60.12 to 62.28) | 31.83 (31.82 to 31.85) |
| process CPU ms/frame | 11.05 (11.04 to 11.08) | 8.23 (8.18 to 8.27) | 11.30 (11.27 to 11.31) |
| process CPU cores | 0.34 (0.34 to 0.34) | 0.50 (0.50 to 0.51) | 0.36 (0.36 to 0.36) |
| main thread CPU ms/frame | 0.56 (0.56 to 0.57) | 2.05 (2.00 to 2.13) | 0.63 (0.63 to 0.64) |
| unveil-render CPU ms/frame | 7.43 (7.41 to 7.46) | 4.51 (4.39 to 4.55) | 7.11 (7.11 to 7.11) |
| unveil-engine CPU ms/frame | 1.00 (0.99 to 1.00) | 0.48 (0.48 to 0.49) | 1.09 (1.09 to 1.11) |
| other threads CPU ms/frame (rusage total minus those three) | 2.07 (2.05 to 2.07) | 1.20 (1.17 to 1.22) | 2.44 (2.44 to 2.48) |
| canvas GPU ms/frame (command buffers) | 0.88 (0.87 to 0.88) | 1.31 (1.26 to 1.31) | 1.06 (1.02 to 1.08) |
| canvas passes per second | 31.06 (30.92 to 31.12) | 56.72 (54.18 to 58.08) | 31.20 (31.15 to 31.42) |
| canvas GPU ms per pass | 0.88 (0.87 to 0.89) | 1.39 (1.37 to 1.45) | 1.08 (1.04 to 1.10) |
| energy mJ/frame (task_energy) | 5.77 (5.75 to 5.78) | 8.38 (8.32 to 8.63) | 5.25 (5.24 to 5.32) |
| power mW (task_energy / wall) | 180 (179 to 180) | 504 (502 to 537) | 167 (167 to 169) |
| task_gpu_utilisation raw units/frame | 0.00 (0.00 to 0.00) | 0.00 (0.00 to 0.00) | 0.00 (0.00 to 0.00) |
| footprint MiB at the end | 588 (588 to 588) | 577 (576 to 578) | 1476 (1465 to 1476) |
| SliderToFrame draft, all ended median ms | 50.53 (50.45 to 50.57) | 49.40 (49.31 to 49.61) | n/a |
| SliderToFrame draft, all ended p95 ms | 66.70 (66.66 to 66.73) | 50.91 (50.77 to 65.60) | n/a |
| SliderToFrame draft, presented only median ms | 50.53 (50.44 to 50.57) | 49.42 (49.33 to 49.57) | n/a |
| SliderToFrame draft, intervals (presented / overtaken) | 897 / 8, 901 / 3, 902 / 3 | 840 / 118, 864 / 78, 798 / 268 | n/a |
| SliderToFrame full, all ended median ms | 66.79 (66.62 to 66.82) | 65.90 (65.86 to 65.96) | 66.78 (66.65 to 66.84) |
| SliderToFrame full, all ended p95 ms | 67.75 (67.43 to 68.37) | 67.40 (67.28 to 67.52) | 76.95 (76.84 to 83.94) |
| SliderToFrame full, presented only median ms | 66.79 (66.62 to 66.82) | 65.82 (65.74 to 65.84) | 66.78 (66.65 to 66.84) |
| SliderToFrame full, intervals (presented / overtaken) | 29 / 0, 29 / 0, 29 / 0 | 856 / 104, 873 / 68, 824 / 242 | 29 / 0, 29 / 0, 29 / 0 |
| engine render wall ms, fit-draft | 14.97 (14.95 to 14.98) | 11.29 (11.24 to 11.33) | n/a |
| engine render-thread CPU ms, fit-draft | 7.45 (7.43 to 7.49) | 4.55 (4.44 to 4.56) | n/a |
| count, fit-draft | 906 (905 to 906) | 845 (802 to 869) | n/a |
| delivery (engine thread: histogram copy + sink copy) wall ms, fit-draft | 0.73 (0.73 to 0.73) | 0.36 (0.35 to 0.36) | n/a |
| delivery CPU ms, fit-draft | 0.73 (0.73 to 0.73) | 0.36 (0.35 to 0.36) | n/a |
| engine render wall ms, fit-full | 13.35 (13.28 to 13.57) | 10.86 (10.62 to 10.91) | 13.62 (13.27 to 13.84) |
| engine render-thread CPU ms, fit-full | 6.31 (6.28 to 6.32) | 4.47 (4.35 to 4.52) | 6.47 (6.30 to 6.55) |
| count, fit-full | 29 (29 to 29) | 960 (942 to 1067) | 29 (29 to 29) |
| delivery (engine thread: histogram copy + sink copy) wall ms, fit-full | 0.70 (0.69 to 0.72) | 0.35 (0.35 to 0.36) | 0.68 (0.65 to 0.70) |
| delivery CPU ms, fit-full | 0.70 (0.69 to 0.72) | 0.35 (0.35 to 0.36) | 0.68 (0.65 to 0.70) |
| SliderToFrame window-draft, all ended median ms | n/a | n/a | 51.43 (51.19 to 51.62) |
| SliderToFrame window-draft, all ended p95 ms | n/a | n/a | 67.37 (67.36 to 67.46) |
| SliderToFrame window-draft, presented only median ms | n/a | n/a | 51.36 (51.02 to 51.50) |
| SliderToFrame window-draft, intervals (presented / overtaken) | n/a | n/a | 891 / 14, 885 / 21, 887 / 18 |
| SliderToFrame window-full, all ended median ms | n/a | n/a | 83.38 (83.25 to 83.39) |
| SliderToFrame window-full, all ended p95 ms | n/a | n/a | 93.75 (93.62 to 100.64) |
| SliderToFrame window-full, presented only median ms | n/a | n/a | 83.24 (83.16 to 83.30) |
| SliderToFrame window-full, intervals (presented / overtaken) | n/a | n/a | 22 / 7, 21 / 8, 20 / 9 |
| engine render wall ms, window-draft | n/a | n/a | 14.72 (14.71 to 14.74) |
| engine render-thread CPU ms, window-draft | n/a | n/a | 6.66 (6.66 to 6.67) |
| count, window-draft | n/a | n/a | 905 (905 to 906) |
| window histogram frame wall ms, window-draft | n/a | n/a | 2.60 (2.60 to 2.61) |
| delivery (engine thread: histogram copy + sink copy) wall ms, window-draft | n/a | n/a | 0.79 (0.78 to 0.79) |
| delivery CPU ms, window-draft | n/a | n/a | 0.79 (0.78 to 0.79) |
| engine render wall ms, window-full | n/a | n/a | 12.87 (12.70 to 13.04) |
| engine render-thread CPU ms, window-full | n/a | n/a | 5.15 (5.09 to 5.22) |
| count, window-full | n/a | n/a | 21 (21 to 22) |
| delivery (engine thread: histogram copy + sink copy) wall ms, window-full | n/a | n/a | 0.63 (0.63 to 0.67) |
| delivery CPU ms, window-full | n/a | n/a | 0.63 (0.63 to 0.67) |

Idle 30 s, editor at rest (RAF 26 MP): CPU 11.0 ms, energy 0.33 mJ, power 0.011 mW, canvas passes 0

#### NEF 46 MP: per-frame cost over a 30 s sweep, median (min to max)

| Metric | fit, draft (drag, full render once a second) | fit, 60 Hz drag with a release every tick (draft and full mixed) | 100 % window, draft (drag) |
|---|---|---|---|
| frames delivered | 936 (933 to 936) | 1803 (1801 to 1805) | 953 (953 to 953) |
| frames per second | 31.18 (31.07 to 31.18) | 60.09 (60.01 to 60.11) | 31.75 (31.75 to 31.76) |
| process CPU ms/frame | 11.24 (11.20 to 11.24) | 8.35 (8.34 to 8.35) | 11.64 (11.58 to 11.64) |
| process CPU cores | 0.35 (0.35 to 0.35) | 0.50 (0.50 to 0.50) | 0.37 (0.37 to 0.37) |
| main thread CPU ms/frame | 0.55 (0.55 to 0.55) | 1.92 (1.92 to 1.95) | 0.60 (0.59 to 0.60) |
| unveil-render CPU ms/frame | 7.71 (7.70 to 7.72) | 4.78 (4.74 to 4.79) | 6.75 (6.72 to 6.76) |
| unveil-engine CPU ms/frame | 0.97 (0.96 to 0.97) | 0.47 (0.47 to 0.47) | 1.95 (1.94 to 1.97) |
| other threads CPU ms/frame (rusage total minus those three) | 2.00 (1.99 to 2.01) | 1.18 (1.17 to 1.19) | 2.32 (2.29 to 2.34) |
| canvas GPU ms/frame (command buffers) | 0.86 (0.85 to 0.86) | 1.36 (1.36 to 1.44) | 0.93 (0.92 to 0.96) |
| canvas passes per second | 30.94 (30.91 to 30.98) | 59.37 (58.67 to 59.42) | 31.02 (30.89 to 31.08) |
| canvas GPU ms per pass | 0.87 (0.85 to 0.87) | 1.38 (1.37 to 1.47) | 0.96 (0.95 to 0.98) |
| energy mJ/frame (task_energy) | 6.07 (6.06 to 6.08) | 8.66 (8.64 to 9.03) | 5.68 (5.62 to 5.69) |
| power mW (task_energy / wall) | 189 (188 to 189) | 519 (519 to 543) | 180 (178 to 181) |
| task_gpu_utilisation raw units/frame | 0.00 (0.00 to 0.00) | 0.00 (0.00 to 0.00) | 0.00 (0.00 to 0.00) |
| footprint MiB at the end | 598 (598 to 598) | 599 (599 to 599) | 1952 (1941 to 1955) |
| SliderToFrame draft, all ended median ms | 50.60 (50.58 to 50.62) | 49.44 (49.44 to 49.47) | n/a |
| SliderToFrame draft, all ended p95 ms | 66.75 (66.69 to 66.79) | 50.91 (50.85 to 64.64) | n/a |
| SliderToFrame draft, presented only median ms | 50.60 (50.57 to 50.61) | 49.43 (49.41 to 49.44) | n/a |
| SliderToFrame draft, intervals (presented / overtaken) | 897 / 6, 896 / 10, 898 / 8 | 855 / 87, 875 / 45, 875 / 48 | n/a |
| SliderToFrame full, all ended median ms | 66.72 (66.68 to 66.77) | 65.99 (65.95 to 66.00) | 67.19 (66.96 to 67.80) |
| SliderToFrame full, all ended p95 ms | 67.94 (67.45 to 68.26) | 66.98 (66.86 to 67.38) | 83.48 (83.33 to 83.75) |
| SliderToFrame full, presented only median ms | 66.72 (66.68 to 66.77) | 65.97 (65.93 to 65.99) | 67.19 (66.96 to 67.80) |
| SliderToFrame full, intervals (presented / overtaken) | 29 / 0, 29 / 0, 29 / 0 | 900 / 41, 900 / 19, 903 / 19 | 29 / 0, 29 / 0, 29 / 0 |
| engine render wall ms, fit-draft | 15.13 (15.12 to 15.14) | 11.53 (11.53 to 11.64) | n/a |
| engine render-thread CPU ms, fit-draft | 7.74 (7.73 to 7.75) | 4.80 (4.78 to 4.82) | n/a |
| count, fit-draft | 907 (904 to 907) | 879 (863 to 880) | n/a |
| delivery (engine thread: histogram copy + sink copy) wall ms, fit-draft | 0.69 (0.69 to 0.70) | 0.35 (0.35 to 0.35) | n/a |
| delivery CPU ms, fit-draft | 0.69 (0.69 to 0.70) | 0.35 (0.35 to 0.35) | n/a |
| engine render wall ms, fit-full | 13.67 (13.52 to 13.69) | 11.13 (11.09 to 11.14) | 14.08 (14.01 to 14.11) |
| engine render-thread CPU ms, fit-full | 6.57 (6.57 to 6.59) | 4.74 (4.69 to 4.74) | 6.68 (6.64 to 6.70) |
| count, fit-full | 29 (29 to 29) | 924 (921 to 942) | 29 (29 to 29) |
| delivery (engine thread: histogram copy + sink copy) wall ms, fit-full | 0.70 (0.69 to 0.70) | 0.34 (0.34 to 0.34) | 0.65 (0.63 to 0.71) |
| delivery CPU ms, fit-full | 0.70 (0.69 to 0.70) | 0.34 (0.34 to 0.34) | 0.65 (0.63 to 0.71) |
| SliderToFrame window-draft, all ended median ms | n/a | n/a | 66.25 (66.20 to 66.31) |
| SliderToFrame window-draft, all ended p95 ms | n/a | n/a | 67.36 (67.35 to 67.52) |
| SliderToFrame window-draft, presented only median ms | n/a | n/a | 66.16 (65.96 to 66.19) |
| SliderToFrame window-draft, intervals (presented / overtaken) | n/a | n/a | 879 / 25, 885 / 21, 878 / 26 |
| SliderToFrame window-full, all ended median ms | n/a | n/a | 83.47 (83.36 to 83.76) |
| SliderToFrame window-full, all ended p95 ms | n/a | n/a | 100.38 (100.23 to 100.39) |
| SliderToFrame window-full, presented only median ms | n/a | n/a | 83.30 (83.10 to 83.40) |
| SliderToFrame window-full, intervals (presented / overtaken) | n/a | n/a | 22 / 7, 19 / 10, 19 / 10 |
| engine render wall ms, window-draft | n/a | n/a | 14.18 (14.17 to 14.21) |
| engine render-thread CPU ms, window-draft | n/a | n/a | 6.26 (6.23 to 6.28) |
| count, window-draft | n/a | n/a | 902 (901 to 904) |
| window histogram frame wall ms, window-draft | n/a | n/a | 2.69 (2.66 to 2.69) |
| delivery (engine thread: histogram copy + sink copy) wall ms, window-draft | n/a | n/a | 1.63 (1.63 to 1.65) |
| delivery CPU ms, window-draft | n/a | n/a | 1.63 (1.63 to 1.65) |
| engine render wall ms, window-full | n/a | n/a | 12.61 (12.42 to 12.71) |
| engine render-thread CPU ms, window-full | n/a | n/a | 4.98 (4.88 to 5.12) |
| count, window-full | n/a | n/a | 22 (20 to 23) |
| delivery (engine thread: histogram copy + sink copy) wall ms, window-full | n/a | n/a | 1.47 (1.45 to 1.47) |
| delivery CPU ms, window-full | n/a | n/a | 1.47 (1.45 to 1.47) |

Idle 30 s, editor at rest (NEF 46 MP): CPU 23.2 ms, energy 1.34 mJ, power 0.043 mW, canvas passes 0


- **Draft is not cheaper than full.** In the same run the engine renders a draft in 14.97 ms wall / 7.45 ms render-thread CPU
  and a full in 13.4 ms / 6.3 ms (RAF), 15.1 / 7.7 and 13.6 / 6.6 on the NEF. They are the same render (profiling.md reached the
  same conclusion). E4 starts from this.
- **CPU per render depends on the load.** The same render costs 7.4 ms of render-thread CPU at 31 frames per second and 4.5 ms at
  60: the cores run at a lower clock when lightly loaded. Compare CPU per frame only within one configuration; energy per frame
  is higher at 60 frames per second (8.4 against 5.8 mJ) because the GPU and the cores are busier.
- **Energy.** `task_energy` is available on iPadOS (nonzero). I read it as nanojoules (the SDK has `ri_energy_nj`, the same
  counter family). It behaves like a CPU-side model estimate: 0.52 mJ per CPU millisecond at 31 frames per second, 1.0 at 60,
  0.03 at idle, and nothing shows GPU or display energy in it. Use it for comparisons between rows of this document only.
  The Power Profiler measurement the spec names was not done (worker rules). `task_gpu_utilisation` is always 0, so GPU busy time
  of the engine is not available from the process counters: the engine's GPU share is bounded by the render wall time minus the
  render thread's CPU time (about 7.5 ms per draft at fit, a proxy). The canvas's own pass is small: 0.84 to 1.5 ms per command
  buffer. Idle (editor at rest, 30 s): 11 to 23 ms of CPU, under 2 mJ, no canvas passes.
- **Latency, as measured.** Draft `SliderToFrame` (all ended) is 50.5 ms at fit and 51.4 ms at 100 % (RAF), 50.6 and 66.3 ms
  (NEF); full 66.8 ms. In this sweep 905 draft intervals ended in 30 s (30 per second); the J1 and Z2 reports of earlier builds
  show about 60 per second and a 35 ms fit draft. The request rate is half of theirs. Not investigated here (a separate bisect
  ticket owns it), so no cause is claimed and no E4 latency gate is set from this number.
- Overhead of the latency hook: the first batch of cost runs (`raw-logs-cost-batch1/`, no latency log, same build otherwise)
  gave 10.98 ms process CPU per frame (RAF, fit, draft) against 11.05 here, so the probes are within noise.

## 4. Biggest owners (RAF, with the NEF in brackets), ranked

Ranking basis: size at the 100 % state (the largest steady state) plus the lifetime peak; the order at fit, the common state, is
given per row. At fit (RAF, MiB) it is: remainder 213, pool 184, preview stages 146, FrameSink 37 touched, preview source 33.

| # | Owner | Size | At fit | Ticket |
|---|---|---|---|---|
| 1 | Memory the allocator keeps after free (decode temporaries), plus the transient peak of the full decode | 0.4 to 0.5 GiB at 100 % and after (footprint after returning to fit 642 to 1065 MiB, NEF 915 to 1750); lifetime peak 2.3 GiB (3.8) | up to 137 MiB | none yet, see 4b |
| 2 | The decoded original twice: CPU f32 and the GPU device copy | 594 MiB (1040) | 0 (no original yet) | E1 (one copy), E2 (half precision on the GPU copy) |
| 3 | GPU buffer pool kept after use | 304 MiB at 100 %, all charged to the footprint | 184 MiB, rank 2 | none yet, see 4b |
| 4 | Resident stages: preview 146 (163), window 126 | 272 MiB (289) | 146, rank 3 | E2 |
| 5 | Preview-level CPU source after the GPU has it | 33 MiB (50) | 33 | E1 |
| 6 | App base, FrameSink, drawables, heap | 72 to 82 idle; FrameSink touched 37 to 63 | 213 incl. retained | none; not a target |

### 4b. Facts for the two tickets without an owner

**Retained allocator memory and the decode peak.**

- Evidence the memory is held, not owned: after the zoom out MALLOC_LARGE is 348 MiB (runs 1 and 3) or 771 (run 2) against 376 MiB
  of heap in use, with the engine's counters naming 330 MiB of sources; a calibration block of 256 MiB freed with `free` and
  `malloc_zone_pressure_relief` stays charged for at least 1 s, and the next 256 MiB allocation reuses it without growing
  (`calibrate-metal-2.log`). The engine calls `pressure_relief` after each decode and after the window release; the footprint
  still differs by 420 MiB between runs 1 and 2 after the same sequence.
- Returnable: yes, by `munmap` or `vm_deallocate` of a block allocated with `mmap`/`vm_allocate` (829 to 573 MiB at once), or by
  `madvise(MADV_FREE_REUSABLE)` on the malloc block before freeing it (573 to 317 MiB at once). Plain `free` is the one that
  does not return it.
- Peak composition, what is known: the steady state at 100 % (RAF) is 297 CPU original + 297 GPU copy + 126 window stages
  + 146 preview stages + 304 pool + 33 preview source + about 210 CPU-side remainder = 1413, measured 1853 (1792 to 2013); the
  peak 2339 (2323 to 2339) is 486 MiB above that median, the same order as the 450 MiB that stays retained afterwards, so the
  retained part is the decode working set. NEF: peak 3786 to 3825 against a 1863 to 2700 steady state, 1.1 to 1.9 GiB of
  working set for a 520 MiB original (2.1 to 3.8 times). Not known: the time profile of the peak (the sampler is 2 s) and
  the split of the working set between file bytes (27.9 and 58.7 MB), 16-bit samples, the float image, intermediates and the
  upload staging. First step of the ticket: sample the footprint at 100 ms through the zoom decode and log the loader's allocations.
- Candidate mechanisms: decode straight into the GPU buffer or in row bands uploaded as they are made; allocate the full-size
  image with `mmap` and `munmap` it (or `madvise(MADV_FREE_REUSABLE)`) when it is dropped; keep the original only on the GPU (E1).
- Gates: lifetime peak under 1.5 GiB (RAF) and 2.5 GiB (NEF); footprint 10 s after the zoom out within 100 MiB of the `fit`
  value, over 3 runs (now up to 640 MiB apart).

**GPU pool cap and trim.**

- Size: 184 MiB pooled at fit after the open's renders (both RAWs), 304 MiB at 100 %, 0 after a window release. The engine caps it
  at an eighth of the memory budget (the budget in the logs is 2.86 GB, so a 341 MiB cap): nothing trims it at fit, and only
  the window release (`trim_pool(0)`, after 2 s without a window) and `uv_suspend` empty it.
- Touched: all of it. The footprint equals the engine GPU buffers plus Metal other within -4 to +22 MiB with the pool at 184, 304
  and 0, so the pool is charged in full and trimming it returns its full size (an upper bound for the saving: the next render
  refills what it needs, and the saving at fit is what the steady render set does not use).
- Acceptance for E1 or a new ticket: pooled bytes at fit under 50 MiB after 5 s idle (or the cap lowered to what a draft
  render needs, to be measured), footprint at fit lower by the trimmed amount, no latency regression in the sweep
  (`-UnveilCost`, same configurations).

## 5. Targets for E1 to E5 (spec's indicative ones)

All "after" estimates below are upper bounds on what is gained (the pool refills, retained memory varies), to be replaced by
E1's own measurement.

| Target | Measured now | Verdict |
|---|---|---|
| Fit under 300 MiB (RAF) | 577 MiB (488 to 579); NEF 746 (511 to 824) | **Confirm for the RAF only if E1, E2 and the pool trim all land**: 577 - 33 (source) - 73 (half stages) - 184 (pool) = 287 MiB at best (the estimate assumes the 184 MiB pool trims to 0 and the retained memory stays as measured). **Revise the NEF to under 350 MiB** (746 - 50 - 82 - 184 = 430 with the retained temporaries, about 200 without) |
| 100 % under 900 MiB (RAF) | 1853 MiB (1792 to 2013), peak 2339 | **Confirm 900, conditional on returning the freed decode memory to the OS** (without it the same arithmetic gives about 1070 MiB at best: 1853 - 297 - 149 - 63 - 73 - 200 pool). **Add a lifetime-peak target**: RAF under 1.5 GiB, NEF under 2.5 GiB (now 2.3 and 3.8) |
| Open under 400 ms | RAF cold 676 / warm 607, NEF cold 1012 / warm 612 | **Revise.** 430 ms of it is the decode and the display pipeline adds 60 to 85; 400 ms is out of reach with one decode of that cost. Either cut the decode (E3 should state a decode time, not only a count: it is already 1 per open, 2 with the first zoom) or define the target as the first pixels (the embedded preview), keeping the final-quality first render under 600 ms warm |
| Draft `SliderToFrame` under 25 ms | 50.5 ms (RAF fit), 51.4 (RAF 100 %), 66.3 (NEF 100 %), at half the request rate of the earlier reports | **Open.** Not confirmed and not revised until the bisect ticket settles the baseline; the render alone is 15 ms wall plus 0.7 ms delivery per frame here |

Suggested measurable gates: draft render-thread CPU per frame under the full's (now equal), CPU per frame at fit and 100 % (E5)
against the table above at the same configuration, footprint after returning to fit within 100 MiB of the `fit` value.

## Limits

- Three runs per measurement; the memory rows after a zoom vary by hundreds of MiB between runs (allocator), so the medians
  there are indicative and the ranges are the result.
- Per-owner "remainder" is a subtraction and mixes the allocator's retained memory with the idle app; section 1 splits it by VM
  tag, but dirty-page counts are not exact and the catalog/journal are not separately measured.
- Full-render-only CPU and energy per frame are not given as a row: a drag always requests a draft before its full render, so
  the 60 Hz configuration is a mix. The per-category engine rows (render wall and render-thread CPU for `fit-full` and
  `window-full`) are the pure full figures.
- The decode load events carry the calling thread's CPU only (the work runs on worker threads); per-thread CPU deltas cover
  threads alive at both ends of a sweep, the total comes from `getrusage`.
- Energy has no stated unit in the SDK header (read as nJ, CPU-side); only comparisons inside this document are safe. GPU busy
  time per process is not available and the Power Profiler was not run.
- The `fit-after` and `zoom` rows come from one zoom per run. Windows at other zoom levels and the NEF at 400 % were not measured.
- Launches failed three times in a row at points when the iPad's screen was locked or asleep (the coordinator confirmed a lock
  from 18:22); those runs were repeated after waking the device. No result in this report comes from a failed launch.
- The measurements were taken before the gating change of the style round; a re-run of the timeline and of one cost sweep
  with the gated build (`raw-logs/gate-*.log`) gave 11.02 ms process CPU per frame, 50.5 ms draft `SliderToFrame` and one decode, as before.
- Tests: see the test lines of `task-e0-report.md` (they were repeated after the style round).
