//
//  PanelSwipeObserver.swift
//  Unveil
//

import UIKit

/// PanelSwipeObserver notices a fast upward swipe on an embedded system browser, so the home
/// panel can expand from its content. It only reads the pan's final velocity: it recognizes
/// simultaneously with everything, never cancels or delays touches, and so never blocks the
/// browser's own scrolling or taps.
final class PanelSwipeObserver: NSObject, UIGestureRecognizerDelegate {

    // Points per second, upward: well above a slow scroll, so reading a list does not expand.
    private static let minimumUpwardVelocity: CGFloat = 900

    var onSwipeUp: () -> Void

    init(onSwipeUp: @escaping () -> Void) {
        self.onSwipeUp = onSwipeUp
    }

    func attach(to view: UIView) {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panChanged(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan   = false
        pan.delaysTouchesEnded   = false
        pan.delegate             = self
        view.addGestureRecognizer(pan)
    }

    @objc
    private func panChanged(_ pan: UIPanGestureRecognizer) {
        guard pan.state == .ended else { return }

        let velocity = pan.velocity(in: pan.view)
        if -velocity.y > Self.minimumUpwardVelocity, abs(velocity.y) > abs(velocity.x) {
            onSwipeUp()
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer                                     : UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
