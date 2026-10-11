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

    /// init(view:) binds the generators to `view`, whose coordinates the tick locations use. A
    /// SwiftUI control gets its view through HapticsAnchor.
    init(view: UIView) {
        selection = UISelectionFeedbackGenerator(view: view)
        canvas    = UICanvasFeedbackGenerator(view: view)
    }

    /// prepare warms the generators up while a gesture runs, so the next tick is not late.
    func prepare() {
        selection.prepare()
        canvas.prepare()
    }

    /// tick(at:) fires the landmark tick at `location`, in the view's coordinates.
    func tick(at location: CGPoint) {
        selection.selectionChanged(at: location)
        canvas.alignmentOccurred(at: location)
    }
}
