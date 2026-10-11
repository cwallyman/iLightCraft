//
//  PanelDragSurface.swift
//  Unveil
//

import SwiftUI
import UIKit

/// PanelDragSurface is the transparent cover over the collapsed panel's browsers. Both browsers
/// are out-of-process remote views, so the host never sees their touches; this cover takes them
/// first instead. A vertical drag on it moves the panel exactly like the header, so the first
/// scroll expands the panel instead of scrolling a list, and a tap expands it.
///
/// The system routes touches on remote views across processes, and how it treats a fully clear
/// layer there is not documented. The cover assumes such a layer might be skipped, so it carries
/// an invisible 2 % black fill; the sturdier guarantee is that while it is up the browsers refuse
/// touches on both the SwiftUI and the UIKit side, so no hit test can resolve to them.
///
/// `isActive` false hides the cover at once (a hidden view takes no touches and is invisible to
/// VoiceOver), so the browser gets every touch from the moment the panel decides to expand. For
/// VoiceOver an active cover is a single "Expand Browser" button.
struct PanelDragSurface: UIViewRepresentable {

    let isActive     : Bool
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded  : (CGFloat, CGFloat) -> Void
    let onExpand     : () -> Void

    func makeUIView(context: Context) -> SurfaceView {
        SurfaceView()
    }

    func updateUIView(
        _ view : SurfaceView,
        context: Context
    ) {
        view.isHidden      = !isActive
        view.onDragChanged = onDragChanged
        view.onDragEnded   = onDragEnded
        view.onExpand      = onExpand
    }

    /// SurfaceView reports its pan in window coordinates: the panel moves under the finger, so a
    /// translation measured in its own space would shrink by the panel's own motion.
    final class SurfaceView: UIView {

        var onDragChanged: (CGFloat) -> Void          = { _ in }
        var onDragEnded  : (CGFloat, CGFloat) -> Void = { _, _ in }
        var onExpand     : () -> Void                 = {}

        override init(frame: CGRect) {
            super.init(frame: frame)

            // Assumption, not documented: cross-process routing might skip a fully clear layer
            // and reach the browser below. 2 % black over the dark browser is invisible anyway.
            backgroundColor        = UIColor.black.withAlphaComponent(0.02)
            isAccessibilityElement = true
            accessibilityLabel     = "Expand Browser"
            accessibilityTraits    = .button

            addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(panned(_:))))
            addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("SurfaceView is built in code, not from a storyboard")
        }

        override func accessibilityActivate() -> Bool {
            onExpand()
            return true
        }

        // Only a mostly vertical drag moves the panel; a sideways one does nothing.
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }

            let velocity = pan.velocity(in: nil)
            return abs(velocity.y) > abs(velocity.x)
        }

        @objc
        private func panned(_ pan: UIPanGestureRecognizer) {
            switch pan.state {
                case .began, .changed:
                    onDragChanged(pan.translation(in: nil).y)

                case .ended, .cancelled:
                    onDragEnded(pan.translation(in: nil).y, pan.velocity(in: nil).y)

                default:
                    break
            }
        }

        @objc
        private func tapped() {
            onExpand()
        }
    }
}
