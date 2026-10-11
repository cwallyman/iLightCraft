//! The `before` flag of uv_request_preview and uv_request_window: the unedited look of the photo.

mod common;
use common::*;
use std::sync::{Arc, Condvar, Mutex};
use std::time::Duration;
use unveil_ffi::*;

/// Shot is one delivered frame: its generation, whether it is a window, its histogram total and
/// its pixels as tight RGBA rows.
#[derive(Clone, Debug)]
struct Shot {
    generation: u64,
    window: bool,
    histogram_total: Option<u32>,
    rgba: Vec<u8>,
}

#[derive(Default)]
struct Shots {
    list: Mutex<Vec<Shot>>,
    cv: Condvar,
}

extern "C" fn keep_shot(ctx: *mut std::ffi::c_void, frame: *const UVFrame) {
    // SAFETY: the engine passes a frame valid for the duration of the callback.
    let f = unsafe { &*frame };
    // SAFETY: the frame's pixels are stride * height readable bytes during the callback.
    let bytes = unsafe { std::slice::from_raw_parts(f.rgba, (f.stride * f.height) as usize) };
    let rgba = bytes
        .chunks_exact(f.stride as usize)
        .flat_map(|row| row[..(f.width * 4) as usize].iter().copied())
        .collect();
    let shot = Shot {
        generation: f.generation,
        window: f.window,
        // SAFETY: a non-NULL histogram is valid during the callback, like the frame.
        histogram_total: unsafe { f.histogram.as_ref() }.map(|h| h.total),
        rgba,
    };
    // SAFETY: ctx is the Shots the test keeps alive in an Arc for the whole session.
    let shots = unsafe { &*(ctx as *const Shots) };
    shots.list.lock().unwrap().push(shot);
    shots.cv.notify_all();
}

fn preview(s: &TestSession, shots: &Arc<Shots>, before: bool) -> u64 {
    let ctx = Arc::as_ptr(shots) as *mut _;
    // SAFETY: s.raw is live; every test declares shots before s, so it outlives the session.
    let g = unsafe { uv_request_preview(s.raw, 256, false, before, Some(keep_shot), ctx) };
    assert!(g > 0, "{}", last_error());
    g
}

fn window(s: &TestSession, shots: &Arc<Shots>, before: bool) -> u64 {
    let ctx = Arc::as_ptr(shots) as *mut _;
    // SAFETY: s.raw is live; every test declares shots before s, so it outlives the session.
    let g = unsafe { uv_request_window(s.raw, 96, 64, 16, 8, 48, 32, false, before, Some(keep_shot), ctx) };
    assert!(g > 0, "{}", last_error());
    g
}

/// shot_at waits up to 30 s for the frame of generation `g`.
fn shot_at(shots: &Shots, g: u64) -> Shot {
    let list = shots.list.lock().unwrap();
    let (list, _) = shots
        .cv
        .wait_timeout_while(list, Duration::from_secs(30), |l| {
            l.iter().all(|f| f.generation < g)
        })
        .unwrap();
    let found = list.iter().find(|f| f.generation == g).cloned();
    found.unwrap_or_else(|| panic!("no frame {g}"))
}

fn set_exposure(s: &TestSession, value: f64) {
    let params = format!(r#"{{"control":"light.exposure","value":{value}}}"#);
    exec_ok(s, "develop.set", &params);
}

#[test]
fn a_before_preview_differs_from_the_edit_and_equals_a_render_after_a_reset() {
    let shots = Arc::new(Shots::default());
    let s = TestSession::new();
    let id = import_fixture(&s);
    set_exposure(&s, 1.5);
    let after = shot_at(&shots, preview(&s, &shots, false));
    let before = shot_at(&shots, preview(&s, &shots, true));
    assert_eq!(after.rgba.len(), before.rgba.len());
    assert_ne!(after.rgba, before.rgba, "the edit must show");
    assert!(
        before.histogram_total.is_some_and(|total| total > 0),
        "a before frame carries its own histogram"
    );
    exec_ok(&s, "develop.reset", &format!(r#"{{"ids":[{id}]}}"#));
    let reset = shot_at(&shots, preview(&s, &shots, false));
    assert_eq!(before.rgba, reset.rgba, "before is the import look");
    // The edit is untouched: asking for before changed no setting.
    set_exposure(&s, 1.5);
    let again = shot_at(&shots, preview(&s, &shots, false));
    assert_eq!(after.rgba, again.rgba);
}

#[test]
fn a_before_window_is_the_unedited_pixels_of_the_window() {
    let shots = Arc::new(Shots::default());
    let s = TestSession::new();
    let id = import_fixture(&s);
    set_exposure(&s, 1.5);
    let after = shot_at(&shots, window(&s, &shots, false));
    let before = shot_at(&shots, window(&s, &shots, true));
    assert!(after.window && before.window);
    assert!(before.histogram_total.is_none(), "a window carries no histogram");
    assert_ne!(after.rgba, before.rgba);
    exec_ok(&s, "develop.reset", &format!(r#"{{"ids":[{id}]}}"#));
    let reset = shot_at(&shots, window(&s, &shots, false));
    assert_eq!(before.rgba, reset.rgba);
}

#[test]
fn before_and_edited_requests_are_kept_apart_by_generation() {
    let shots = Arc::new(Shots::default());
    let s = TestSession::new();
    import_fixture(&s);
    set_exposure(&s, 1.5);
    let edited = shot_at(&shots, preview(&s, &shots, false));
    let unedited = shot_at(&shots, preview(&s, &shots, true));
    shots.list.lock().unwrap().clear();
    // A burst that alternates the looks: only the newest of the pending ones may follow the first.
    let mut last = 0;
    for i in 0..8 {
        last = preview(&s, &shots, i % 2 == 1);
    }
    let newest = shot_at(&shots, last);
    assert_eq!(newest.rgba, unedited.rgba, "the newest request was a before");
    let tail = preview(&s, &shots, false);
    assert_eq!(
        shot_at(&shots, tail).rgba,
        edited.rgba,
        "an edited request after it shows the edit"
    );
    let list = shots.list.lock().unwrap();
    assert!(
        list.windows(2).all(|w| w[0].generation < w[1].generation),
        "generations must increase: {:?}",
        list.iter().map(|f| f.generation).collect::<Vec<_>>()
    );
    // Generations 1 and 2 were the edited and the before look, then the burst alternated from 3:
    // every delivered frame shows the look its own generation asked for (even: before).
    for shot in list.iter() {
        assert_eq!(
            shot.rgba == unedited.rgba,
            shot.generation % 2 == 0,
            "frame {}",
            shot.generation
        );
    }
}
