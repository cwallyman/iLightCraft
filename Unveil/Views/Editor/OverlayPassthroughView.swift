//
//  OverlayPassthroughView.swift
//  Unveil
//

import UIKit

/// OverlayPassthroughView holds the SwiftUI overlay and lets every touch outside its controls
/// through to the canvas below.
///
/// A UIHostingController's view answers `hitTest` with itself at every point, empty or not (the
/// SwiftUI controls are not UIViews, so it cannot tell), and a full-screen overlay would swallow
/// every pinch and pan meant for the canvas. The overlay reports the window frames of what it
/// draws (`touchableFrames`), and this view only hit-tests its subviews inside them; anywhere
/// else it answers nil and UIKit moves on to the canvas.
final class OverlayPassthroughView: UIView {

    private let touchableFrames: () -> [CGRect]

    init(touchableFrames: @escaping () -> [CGRect]) {
        self.touchableFrames = touchableFrames

        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("OverlayPassthroughView is built in code, not from a storyboard")
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let windowPoint = convert(point, to: nil)

        guard touchableFrames().contains(where: { $0.contains(windowPoint) }) else { return nil }

        return super.hitTest(point, with: event)
    }
}
