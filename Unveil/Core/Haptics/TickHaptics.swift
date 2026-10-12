//
//  TickHaptics.swift
//  Unveil
//

import UIKit

/// TickHaptics gives the one light tick of a landmark (the canvas passing fit or 100 %, a slider
/// passing its default or reaching an end) on whatever the user is holding.
///
/// UISelectionFeedbackGenerator speaks to the device's own Taptic Engine, which an iPad does not
/// have, so on its own a tick is felt nowhere. UICanvasFeedbackGenerator speaks to indirect input
/// with a haptic engine of its own, the Magic Keyboard's haptic trackpad and Apple Pencil Pro, the
/// way the system's alignment guides do: it needs the view and the location of the pointer or tip.
/// A tick fires both; each device answers only to its own.
@MainActor
final class TickHaptics {

    private let selection: UISelectionFeedbackGenerator
    private let canvas   : UICanvasFeedbackGenerator

    /// preparedAt is when the generators were last warmed up; prepareInterval is how long that lasts
    /// for this type's purpose. A gesture calls `prepare` on every step, and each call cost the
    /// main thread 0.1 to 0.4 ms (6.8 ms once) on the iPad, so the calls in between are skipped.
    private var preparedAt: ContinuousClock.Instant?
    private static let prepareInterval = Duration.seconds(1)

    /// init(view:) binds the generators to `view`, whose coordinates the tick locations use. A
    /// SwiftUI control gets its view through HapticsAnchor.
    init(view: UIView) {
        selection = UISelectionFeedbackGenerator(view: view)
        canvas    = UICanvasFeedbackGenerator(view: view)
    }

    /// prepare warms the generators up while a gesture runs, so the next tick is not late, at most
    /// once per `prepareInterval` (the system keeps them ready for a few seconds).
    func prepare() {
        let now = ContinuousClock.now

        if let preparedAt, preparedAt.duration(to: now) < Self.prepareInterval { return }

        preparedAt = now
        selection.prepare()
        canvas.prepare()
    }

    /// tick(at:) fires the landmark tick at `location`, in the view's coordinates. A fired feedback
    /// ends the generators' prepared state, so the next `prepare` warms them again.
    func tick(at location: CGPoint) {
        selection.selectionChanged(at: location)
        canvas.alignmentOccurred(at: location)
        preparedAt = nil
    }
}
