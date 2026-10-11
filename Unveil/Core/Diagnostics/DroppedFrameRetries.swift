//
//  DroppedFrameRetries.swift
//  Unveil
//

/// DroppedFrameRetries decides what the canvas does with a drawable that reports no presented time.
///
/// A drawable presented while the canvas is not really on screen (the editor still fading in over
/// the home, the first frame of an open landing in the fade) is reported with a presented time of
/// 0 although the pass ran: the frame was not shown. The canvas draws it again on its next tick,
/// and only once `limit` has passed since the first drop of a run (a canvas that stays hidden)
/// gives up and lets the signposts report `dropped`, so a hidden canvas never redraws forever.
///
/// The bound is a time, not a count, so it covers the same span at 60 and 120 Hz: one second is
/// well past the 0.35 s fade. The caller passes the time, so the rule is unit tested without a clock.
nonisolated struct DroppedFrameRetries {

    let limit: Duration

    private(set) var firstDrop: ContinuousClock.Instant?

    init(limit: Duration = .seconds(1)) {
        self.limit = limit
    }

    /// shouldDrawAgain records one presented drawable at `now` and returns whether the same frame
    /// must be drawn again: true for a drop within the limit. A presented drawable starts over.
    mutating func shouldDrawAgain(isDropped: Bool, at now: ContinuousClock.Instant) -> Bool {
        guard isDropped else {
            firstDrop = nil
            return false
        }

        let start = firstDrop ?? now

        guard now - start < limit else {
            firstDrop = nil
            return false
        }

        firstDrop = start

        return true
    }
}
