# Engine commands for v0 (T4)

The sequence Swift runs through `uv_execute(session, command, params_json, &result)`. Results below are real output
from `Engine/ffi/tests/commands.rs` (library in a temp dir, 96x64 PNG fixture).

## Status mapping

| Case | Status | `uv_last_error` |
|---|---|---|
| `params_json` is not valid JSON | `UV_ERR_INVALID_ARGUMENT` | `params_json: ...` (serde_json message) |
| command name unknown | `UV_ERR_UNKNOWN_COMMAND` | from the engine |
| any other engine failure | `UV_ERR_ENGINE` | engine message, e.g. `invalid parameters for `develop.set`: unknown control `nope.x`` |
| `develop.set` with no active photo | `UV_ERR_ENGINE` | contains `no photo selected` |

A bad control id is an engine error (`UV_ERR_ENGINE`), not `UV_ERR_INVALID_ARGUMENT`: only the JSON syntax is checked in the FFI.
`params_json` NULL means `{}`. `develop.set` returns JSON `null`.

## Sequence

1. `library.import` `{"paths":["/abs/path/photo.ARW"],"mode":"add"}`
   ```json
   {"duplicates":[],"failed":[],"imported":[1],"scanned":1,"sidecars":0}
   ```
   `imported` holds the new photo ids (u64). A file the engine cannot read goes to `failed` as `[path, reason]` and
   `imported` stays empty (the call still succeeds; path shortened here, the real one is the test temp dir):
   ```json
   {"duplicates":[],"failed":[["/tmp/broken.ARW","unrecognized file format"]],"imported":[],"scanned":1,"sidecars":0}
   ```
   Importing a path (`"reason":"path"`) or bytes (`"reason":"content"`) already in the library imports nothing and
   reports the existing photo (real output, path shortened):
   ```json
   {"duplicates":[{"existing":1,"path":"/tmp/fixture.png","reason":"path"}],"failed":[],"imported":[],"scanned":1,"sidecars":0}
   ```
   **Getting the photo id:** `imported[0]`, else `duplicates[0].existing`, else `restored[0]` (the engine's
   `restored` array, filled when a trashed photo is brought back by an `onDeleted` restore; not observed
   in the tests). Then call `library.select` with that id, so reopening a photo works like a first open.
   The engine already makes the first imported photo active.
2. `library.select` `{"ids":[1],"active":1}`
   ```json
   {"selected":1}
   ```
   Redundant after step 1, but it is the documented sequence for Swift (same as the engine's MCP tools), so keep it.
3. `develop.set` `{"control":"light.exposure","value":0.5}` returns `null`. Values outside a control's range are clamped, not rejected.

Control ids: `light.exposure`, `light.contrast`, `light.highlights`, `light.shadows`, `light.whites`, `light.blacks`,
`wb.temp` (Kelvin, e.g. 5000), `wb.tint`, `color.vibrance`, `color.saturation`.

## Parameterless check

`library.info` with `{}` or NULL returns a large object (library path, cache and persistence counters). Fields worth
reading: `photos` (count), `persistent`, `lastError`. Excerpt after the sequence above:

```json
{"albums":0,"lastError":null,"persistent":true,"photos":1,"seq":2,"unsavedError":null,"unsavedOps":0, "...":"..."}
```

## Previews and zoom windows (ABI 2)

Frames are not commands: they come from `uv_request_preview` (the whole frame fitted in `max_pixels`) and, since
ABI 2, `uv_request_window(session, full_w, full_h, x, y, w, h, draft, cb, ctx)`: the `(x, y, w, h)` pixels of the
frame fitted in `full_w x full_h`, for a canvas zoomed past the preview's own resolution. Both return a generation at
once and deliver later, on the engine thread, through `uv_frame_cb(ctx, const UVFrame *)`.

| `UVFrame` field | Whole-frame preview | Window |
|---|---|---|
| `width`, `height`, `stride`, `rgba` | the frame | the window, clamped inside the frame |
| `window` | false | true |
| `fallback` | true only for the whole frame answering a window that cannot render alone | false |
| `frame_width`, `frame_height` | = `width`, `height` | the whole frame as the render fits it in `full_w x full_h` |
| `x`, `y` | 0 | the window's origin in that frame |
| `native_width`, `native_height` | the whole frame at the photo's own resolution | the same |

`native_width x native_height` is what 100 % means: the oriented, cropped and straightened frame at the photo's
recorded size (the size a full-size export writes), from the same geometry upstream's `region_job` builds for the
window (`Frame::with_lens(...).native_size()`). The app measures its zoom percentage and the window's frame against
it, so 100 % of a crop is the crop's own pixels. It ignores an automatic Upright stored without its transform (only
XMP-imported settings) and the decoded source's size, either of which can move it by a pixel.

- **Scheduling.** One render in flight; the newest pending request wins, with one refinement: a window never replaces a
  pending preview (the app draws the window over it, so the preview renders first), while a preview replaces every older
  pending window and a window older than the pending preview is dropped. Frames still arrive in increasing generations.
- **Stages.** The preview and the window keep separate resident stages (they read different source levels and sizes); both
  are dropped on photo change and on `uv_suspend`, and `uv_set_memory_budget` keeps them within a quarter of the budget
  together, dropping the window's first. The window's source is upstream's one shared device copy of the original, emptied
  by `uv_suspend` with the buffer pool.
- **Release.** `uv_release_windows(session)` (void, never waits) drops the window's stages at once and, as soon as no
  render is in flight, empties the GPU buffer pool with `trim_pool(0)`, which also frees the shared device copy of the
  original, then returns freed heap pages (`memory::release`). A window request that arrives before that cancels the rest.
  The app calls it once the canvas has wanted no window for 2 s. The decoded original stays in the engine's budgeted
  source cache (dropping it alone would need a `MediaCache` method, a crate change), so the next window only uploads it.
- **Fallback.** When `region_job` refuses the window (a spot reads farther than 8192 px), the frame delivered is the
  whole-frame preview fitted in `max(w, h)`, with `window` false and `fallback` true: the app shows it as the preview and
  drops the window it showed (older, maybe of older settings). The same fallback asked again (same settings, size and
  quality: a pan within the spot's reach) is not rendered and never delivered.
- **Errors.** As `uv_request_preview`, then a frame or window size of 0 (`UV_ERR_INVALID_ARGUMENT`, "size is 0").
- **Failed renders (ABI 3).** `UVFrame` gains `status` (`UV_OK` for a frame) and `error`. A render that fails (its source
  cannot be loaded, the engine errors: `UV_ERR_ENGINE`; the render thread panics: `UV_ERR_PANIC`) is delivered through the
  same callback as a frame with `status` set, `error` its message (valid during the call only), `rgba` NULL, the sizes 0,
  and `generation`, `draft`, `window`, `fallback` of the failed request. It follows the frames' generation rules: only an
  outcome newer than the last delivered one, for the still active photo, is reported, so a failure never follows a newer
  frame or failure. The app keeps the last good frame, shows the message without blocking, and treats a failed window as
  no window (the fit preview stays).
- **Histogram (ABI 4).** `UVFrame` gains `histogram`, a `const UVHistogram *` valid during the call: for every whole frame
  (preview or fallback, draft or full) the engine's own `Rendered.histogram` (`Histogram::of_srgb8`, computed with every
  render), 256 `uint32_t` bins each for `r`, `g`, `b` and `luma` (`(54 R + 183 G + 19 B) >> 8`) over at most about 1 MP
  sampled on a grid (`total` is the pixels sampled), plus `clipped_low[3]` and `clipped_high[3]`, the sampled pixels at 0
  and 255 in R, G, B. It is NULL for a window (its histogram would cover only the window, and the app's describes the
  whole photo) and for a failure. Copying it costs about 4 KB per frame on the engine thread. The app shows it at the top
  of the adjust card, updated on drafts at fit; zoomed in, drafts render only the window, so the histogram holds until
  the next whole frame (the full preview on release). A clipping indicator lights above 0.1 % of the pixels at an end in
  one channel, tinted by the clipped channels (white when all three, or luminance, reach the end); the canvas overlay
  itself tests every displayed pixel (any channel at 0 or 255) in `Canvas.metal`.
- **Accuracy** (`Engine/ffi/tests/window.rs`). On a PNG the window is bytewise equal to the same pixels of the whole frame
  rendered at that size. On the five test RAWs at 100 % the reported frame size equals the whole-frame render's, and inside
  a 32 px margin the window matches its crop to mean ΔE2000 0.0000 to 0.0007, p99 0.000 (max 0 to 1.19); the outer 32 px
  reach ΔE 6.5 (spatial stages see less around the edge), which is why the app asks for that margin.
