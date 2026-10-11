// uv.h: C ABI of the Unveil engine bridge. Version 3.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#define UV_ABI_VERSION 3

typedef enum UVStatus {
    UV_OK                    =  0,
    UV_ERR_INVALID_ARGUMENT  = -1,
    UV_ERR_UNKNOWN_COMMAND   = -2,
    UV_ERR_ENGINE            = -3,
    UV_ERR_PANIC             = -4,
    UV_ERR_SUSPENDED         = -5,
    UV_ERR_IO                = -6,
    UV_ERR_TIMEOUT           = -7,
} UVStatus;

typedef struct UVSession UVSession;

/// One delivered frame: `height` rows of `stride` bytes of RGBA8. A whole-frame preview has
/// `window` false, frame_width/frame_height equal to width/height and x = y = 0. A window
/// (uv_request_window) has `window` true and sits at (x, y) of a frame_width x frame_height frame.
/// `fallback` marks the whole frame answering a window that could not render alone: it replaces
/// the window shown. native_width x native_height is the whole frame at the photo's own resolution
/// (cropped and straightened, as a full-size export): the frame at 100 %.
/// `status` is UV_OK for a frame. A render that failed (its source cannot be loaded, the engine
/// errors or panics) is delivered as a frame with `status` set (UV_ERR_ENGINE or UV_ERR_PANIC),
/// `error` its message (valid only during the call), `rgba` NULL and the sizes 0; `generation`,
/// `draft` and `window` say which request failed. Only the newest request's outcome is delivered,
/// frame or failure, under the same generation rules.
typedef struct UVFrame {
    const uint8_t *rgba;
    uint32_t       width;
    uint32_t       height;
    uint32_t       stride;
    uint64_t       generation;
    bool           draft;
    bool           window;
    bool           fallback;
    uint32_t       frame_width;
    uint32_t       frame_height;
    uint32_t       x;
    uint32_t       y;
    uint32_t       native_width;
    uint32_t       native_height;
    int32_t        status;
    const char    *error;
} UVFrame;

/// Called on the engine thread; `frame` and its pixels are valid only during the call.
typedef void (*uv_frame_cb)(void *ctx, const UVFrame *frame);

uint32_t    uv_abi_version(void);
UVSession  *uv_session_new(const char *data_dir, uint64_t memory_budget);
void        uv_session_free(UVSession *session);

int32_t     uv_execute(UVSession *session, const char *command, const char *params_json,
                       char **result_json);
void        uv_string_free(char *string);
const char *uv_last_error(void);

/// Callable from any thread; the newest generation always wins.
uint64_t    uv_request_preview(UVSession *session, uint32_t max_pixels, bool draft,
                               uv_frame_cb callback, void *ctx);
/// The (x, y, w, h) window of the frame fitted in full_w x full_h, same generations. A window
/// never replaces a pending preview (it is drawn over it); a preview replaces older windows.
/// A window that cannot render alone falls back to the whole frame fitted in max(w, h), with
/// `fallback` set; the same fallback asked again is not rendered.
uint64_t    uv_request_window(UVSession *session, uint32_t full_w, uint32_t full_h,
                              uint32_t x, uint32_t y, uint32_t w, uint32_t h, bool draft,
                              uv_frame_cb callback, void *ctx);
/// Frees what windows keep resident (their stages, then, once no render is in flight, the GPU
/// buffer pool with the shared full-size source); never waits. A later window rebuilds them.
void        uv_release_windows(UVSession *session);

/// UV_OK once no render is in flight (at most 2 s, else UV_ERR_TIMEOUT and the session stays
/// suspended). Previews then fail with UV_ERR_SUSPENDED, and GPU rendering is off for uv_execute too.
int32_t     uv_suspend(UVSession *session);
/// Re-enables the GPU and previews, and clears a recorded GPU failure. A lost GPU device is not
/// recreated in v0: rendering stays on the CPU until the app is relaunched.
int32_t     uv_resume(UVSession *session);
void        uv_set_memory_budget(UVSession *session, uint64_t bytes);
