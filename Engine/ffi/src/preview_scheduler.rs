//! PreviewScheduler decides which preview request renders next, without touching the engine.

pub trait Request {
    fn generation(&self) -> u64;

    /// True for a window of a zoomed frame (uv_request_window), false for a whole-frame preview.
    fn is_window(&self) -> bool;
}

/// PreviewScheduler keeps at most one render in flight and remembers only the newest request:
/// a slider fires faster than the engine renders, and every older value is already stale.
///
/// Whole-frame previews and windows share one generation counter, and the newest wins with one
/// refinement. The app draws a window on top of the whole-frame preview, so a window never
/// replaces a pending preview: both wait, and the preview renders first. A preview does replace
/// every older pending window, because the app never draws a window older than the preview under
/// it. A window older than the pending preview is dropped for the same reason. So the pending
/// preview, when there is one, is always older than the pending window, renders before it, and
/// frames still reach the callback in increasing generations.
pub struct PreviewScheduler<R> {
    in_flight: Option<u64>,
    pending_fit: Option<R>,
    pending_window: Option<R>,
    last_delivered: u64,
}

impl<R> Default for PreviewScheduler<R> {
    // Hand-written: a derive would demand `R: Default`.
    fn default() -> Self {
        Self {
            in_flight: None,
            pending_fit: None,
            pending_window: None,
            last_delivered: 0,
        }
    }
}

impl<R: Request> PreviewScheduler<R> {
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the request to start now, or None when one is already rendering (it becomes pending,
    /// see the type doc for how previews and windows replace each other). A request older than the
    /// pending one of its kind is dropped: callers on several threads can send their generations out
    /// of order, and the newest must win.
    pub fn submit(&mut self, request: R) -> Option<R> {
        if self.in_flight.is_none() {
            self.in_flight = Some(request.generation());
            return Some(request);
        }
        let generation = request.generation();
        let is_older = |pending: &Option<R>| pending.as_ref().is_some_and(|p| p.generation() > generation);
        if request.is_window() {
            if !is_older(&self.pending_window) && !is_older(&self.pending_fit) {
                self.pending_window = Some(request);
            }
        } else if !is_older(&self.pending_fit) {
            // A window newer than this preview stays: it is drawn on top of it.
            if !is_older(&self.pending_window) {
                self.pending_window = None;
            }
            self.pending_fit = Some(request);
        }
        None
    }

    /// Marks `generation` finished; returns the pending request to start next, if any: the preview
    /// before the window, which is the older of the two.
    pub fn finished(&mut self, generation: u64) -> Option<R> {
        if self.in_flight == Some(generation) {
            self.in_flight = None;
        }
        let next = self.pending_fit.take().or_else(|| self.pending_window.take())?;
        self.in_flight = Some(next.generation());
        Some(next)
    }

    /// True when a finished render should reach the callback: newer than anything delivered, and
    /// still for the active photo.
    pub fn should_deliver(
        &mut self,
        generation: u64,
        rendered_photo: u64,
        active_photo: Option<u64>,
    ) -> bool {
        if generation <= self.last_delivered || active_photo != Some(rendered_photo) {
            return false;
        }
        self.last_delivered = generation;
        true
    }

    /// Drops the pending requests (used by suspend and shutdown).
    pub fn clear_pending(&mut self) {
        self.pending_fit = None;
        self.pending_window = None;
    }

    pub fn is_idle(&self) -> bool {
        self.in_flight.is_none() && self.pending_fit.is_none() && self.pending_window.is_none()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Debug, PartialEq)]
    struct R(u64);
    impl Request for R {
        fn generation(&self) -> u64 {
            self.0
        }
        fn is_window(&self) -> bool {
            false
        }
    }

    /// K is a whole-frame preview or a window, for the tests that mix the two kinds.
    #[derive(Debug, PartialEq)]
    enum K {
        Fit(u64),
        Window(u64),
    }
    impl Request for K {
        fn generation(&self) -> u64 {
            match self {
                K::Fit(g) | K::Window(g) => *g,
            }
        }
        fn is_window(&self) -> bool {
            matches!(self, K::Window(_))
        }
    }

    #[test]
    fn idle_scheduler_starts_immediately() {
        let mut s = PreviewScheduler::new();
        assert_eq!(s.submit(R(1)), Some(R(1)));
    }

    #[test]
    fn requests_during_a_render_keep_only_the_newest() {
        let mut s = PreviewScheduler::new();
        s.submit(R(1));
        for g in 2..=10 {
            assert_eq!(s.submit(R(g)), None);
        }
        assert_eq!(s.finished(1), Some(R(10)));
        assert_eq!(s.finished(10), None);
        assert!(s.is_idle());
    }

    #[test]
    fn older_or_foreign_results_are_not_delivered() {
        let mut s: PreviewScheduler<R> = PreviewScheduler::new();
        assert!(s.should_deliver(5, 7, Some(7)));
        assert!(!s.should_deliver(4, 7, Some(7)), "older than delivered");
        assert!(!s.should_deliver(6, 7, Some(8)), "photo no longer active");
        assert!(!s.should_deliver(7, 7, None), "no active photo");
    }

    #[test]
    fn an_older_request_arriving_late_does_not_replace_a_newer_pending_one() {
        let mut s = PreviewScheduler::new();
        s.submit(R(1));
        s.submit(R(5));
        assert_eq!(s.submit(R(4)), None);
        assert_eq!(s.finished(1), Some(R(5)));
    }

    #[test]
    fn clear_pending_drops_the_waiting_request() {
        let mut s = PreviewScheduler::new();
        s.submit(R(1));
        s.submit(R(2));
        s.clear_pending();
        assert_eq!(s.finished(1), None);
    }

    #[test]
    fn a_preview_replaces_an_older_pending_window() {
        let mut s = PreviewScheduler::new();
        s.submit(K::Fit(1));
        assert_eq!(s.submit(K::Window(2)), None);
        assert_eq!(s.submit(K::Fit(3)), None);
        assert_eq!(s.finished(1), Some(K::Fit(3)));
        assert_eq!(s.finished(3), None);
        assert!(s.is_idle());
    }

    #[test]
    fn a_window_waits_behind_the_pending_preview_it_is_drawn_over() {
        let mut s = PreviewScheduler::new();
        s.submit(K::Window(1));
        s.submit(K::Fit(2));
        s.submit(K::Window(3));
        assert_eq!(s.submit(K::Window(4)), None);
        assert_eq!(s.finished(1), Some(K::Fit(2)));
        assert_eq!(s.finished(2), Some(K::Window(4)));
        assert_eq!(s.finished(4), None);
    }

    #[test]
    fn out_of_order_requests_never_deliver_an_older_generation_after_a_newer_one() {
        let mut s = PreviewScheduler::new();
        s.submit(K::Fit(1));
        s.submit(K::Window(5));
        assert_eq!(
            s.submit(K::Fit(4)),
            None,
            "an older preview keeps the newer window"
        );
        assert_eq!(
            s.submit(K::Window(3)),
            None,
            "a window older than the pending preview"
        );
        assert_eq!(s.finished(1), Some(K::Fit(4)));
        assert_eq!(s.finished(4), Some(K::Window(5)));
        assert_eq!(s.finished(5), None);
    }
}
