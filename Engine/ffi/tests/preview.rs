mod common;
use common::*;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use unveil_ffi::*;

fn request(s: &TestSession, max: u32, draft: bool, frames: &Arc<Frames>) -> u64 {
    // SAFETY: s.raw is live; every test declares frames before s, so it outlives the session.
    unsafe {
        uv_request_preview(
            s.raw,
            max,
            draft,
            false,
            Some(record),
            Arc::as_ptr(frames) as *mut _,
        )
    }
}

#[test]
fn a_preview_arrives_with_sane_geometry() {
    let frames = Arc::new(Frames::default());
    let s = TestSession::new();
    import_fixture(&s);
    let g = request(&s, 512, false, &frames);
    assert!(g >= 1, "{}", last_error());
    let got = wait_for(&frames, 1);
    let (generation, draft, w, h, stride, nonzero) = got[0];
    assert_eq!((generation, draft), (g, false));
    assert!(w > 0 && h > 0 && w <= 512 && h <= 512);
    assert_eq!(stride, w * 4);
    assert!(nonzero > 0, "image is all zeros");
}

#[test]
fn a_burst_ends_with_the_newest_generation() {
    let frames = Arc::new(Frames::default());
    let s = TestSession::new();
    import_fixture(&s);
    let mut last = 0;
    for i in 0..10 {
        exec_ok(
            &s,
            "develop.set",
            &format!(r#"{{"control":"light.exposure","value":{}}}"#, i as f64 / 10.0),
        );
        last = request(&s, 256, i < 9, &frames);
    }
    std::thread::sleep(Duration::from_secs(3));
    let got = frames.list.lock().unwrap().clone();
    assert!(!got.is_empty());
    assert!(
        got.windows(2).all(|w| w[0].0 < w[1].0),
        "generations must increase: {got:?}"
    );
    let final_frame = got.last().unwrap();
    assert_eq!(
        (final_frame.0, final_frame.1),
        (last, false),
        "last frame must be the final full render"
    );
}

#[test]
fn no_callback_after_free_returns() {
    let frames = Arc::new(Frames::default());
    {
        let s = TestSession::new();
        import_png(&s, &gradient_png(s.dir.path(), "big.png", 3000, 2000));
        request(&s, 2048, false, &frames);
    } // uv_session_free runs here, with the render likely still in flight
    let n = frames.list.lock().unwrap().len();
    std::thread::sleep(Duration::from_millis(500));
    assert_eq!(frames.list.lock().unwrap().len(), n);
}

#[test]
fn preview_without_an_active_photo_is_an_error() {
    let s = TestSession::new();
    // SAFETY: s.raw is live; ctx is never used: the request fails before queueing.
    let g = unsafe { uv_request_preview(s.raw, 256, false, false, Some(record), std::ptr::null_mut()) };
    assert_eq!(g, 0);
    assert!(last_error().contains("no active photo"), "{}", last_error());
    // The missing photo wins over the missing callback.
    // SAFETY: s.raw is live; ctx is never used: the request fails before queueing.
    let g = unsafe { uv_request_preview(s.raw, 256, false, false, None, std::ptr::null_mut()) };
    assert_eq!(g, 0);
    assert!(last_error().contains("no active photo"), "{}", last_error());
}

#[test]
fn a_null_callback_is_an_invalid_argument() {
    let s = TestSession::new();
    import_fixture(&s);
    // SAFETY: s.raw is live; ctx is never used: the request fails before queueing.
    let g = unsafe { uv_request_preview(s.raw, 256, false, false, None, std::ptr::null_mut()) };
    assert_eq!(g, 0);
    assert!(last_error().contains("callback"), "{}", last_error());
}

#[test]
fn a_result_for_a_photo_no_longer_active_is_dropped() {
    let frames = Arc::new(Frames::default());
    let s = TestSession::new();
    let wide = import_png(&s, &gradient_png(s.dir.path(), "wide.png", 3000, 2000));
    let tall = import_png(&s, &gradient_png(s.dir.path(), "tall.png", 64, 96));
    exec_ok(
        &s,
        "library.select",
        &format!(r#"{{"ids":[{wide}],"active":{wide}}}"#),
    );
    // The wide render takes far longer than the select below, so it finishes for an inactive photo.
    request(&s, 1024, false, &frames);
    exec_ok(
        &s,
        "library.select",
        &format!(r#"{{"ids":[{tall}],"active":{tall}}}"#),
    );
    let g = request(&s, 1024, false, &frames);
    let got = wait_for(&frames, 1);
    std::thread::sleep(Duration::from_millis(500));
    let got_later = frames.list.lock().unwrap().clone();
    assert_eq!(got, got_later, "one frame only: {got_later:?}");
    let (generation, _, w, h, _, _) = got[0];
    assert_eq!(generation, g);
    assert!(h > w, "the frame must be the tall photo: {w}x{h}");
}

/// Failure is what the callback saw of a failed render: its generation, status and message.
type Failure = (u64, i32, String);

#[derive(Default)]
struct Failures(Mutex<Vec<Failure>>);

extern "C" fn record_failure(ctx: *mut std::ffi::c_void, frame: *const UVFrame) {
    // SAFETY: the engine passes a frame valid for the duration of the callback.
    let f = unsafe { &*frame };
    // SAFETY: ctx is the Failures the test keeps alive in an Arc for the whole session.
    let failures = unsafe { &*(ctx as *const Failures) };
    let message = if f.error.is_null() {
        String::new()
    } else {
        // SAFETY: a failed frame's error is a NUL-terminated string valid during the callback.
        unsafe { std::ffi::CStr::from_ptr(f.error) }
            .to_string_lossy()
            .into_owned()
    };
    assert!(
        f.status == 0 || f.rgba.is_null(),
        "a failed frame carries no pixels"
    );
    assert!(
        f.status == 0 || f.histogram.is_null(),
        "a failed frame carries no histogram"
    );
    failures.0.lock().unwrap().push((f.generation, f.status, message));
}

#[test]
fn a_render_that_cannot_load_its_source_is_reported() {
    let failures = Arc::new(Failures::default());
    let s = TestSession::new();
    let png = gradient_png(s.dir.path(), "gone.png", 3000, 2000);
    import_png(&s, &png);
    std::fs::remove_file(&png).unwrap();
    // SAFETY: s.raw is live; failures outlives the session (declared before it).
    let g = unsafe {
        uv_request_preview(
            s.raw,
            512,
            false,
            false,
            Some(record_failure),
            Arc::as_ptr(&failures) as *mut _,
        )
    };
    assert!(g >= 1, "{}", last_error());
    for _ in 0..300 {
        if !failures.0.lock().unwrap().is_empty() {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    let got = failures.0.lock().unwrap().clone();
    assert_eq!(got.len(), 1, "{got:?}");
    assert_eq!((got[0].0, got[0].1), (g, UVStatus::UV_ERR_ENGINE as i32));
    assert!(!got[0].2.is_empty());
}

#[test]
fn only_the_newest_failure_is_reported() {
    let failures = Arc::new(Failures::default());
    let s = TestSession::new();
    let png = gradient_png(s.dir.path(), "gone.png", 3000, 2000);
    import_png(&s, &png);
    std::fs::remove_file(&png).unwrap();
    let mut last = 0;
    for _ in 0..5 {
        // SAFETY: as above.
        last = unsafe {
            uv_request_preview(
                s.raw,
                512,
                false,
                false,
                Some(record_failure),
                Arc::as_ptr(&failures) as *mut _,
            )
        };
    }
    std::thread::sleep(Duration::from_secs(3));
    let got = failures.0.lock().unwrap().clone();
    assert!(!got.is_empty(), "{got:?}");
    assert!(got.windows(2).all(|w| w[0].0 < w[1].0), "{got:?}");
    assert_eq!(got.last().unwrap().0, last, "{got:?}");
}
