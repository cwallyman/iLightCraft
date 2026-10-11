//
//  ZoomIndicatorView.swift
//  Unveil
//

import UIKit

/// ZoomIndicatorView is the small glass capsule that shows the zoom ("Fit", "100%", "250%")
/// while the canvas zooms, then fades out on its own.
///
/// It never takes touches and VoiceOver skips it: the canvas speaks the zoom as its own value.
/// It appears and disappears by animating its `effect` to and from nil, which is how glass
/// materializes; fading the alpha of a visual effect view breaks the effect mid-fade. Each
/// `show` pushes the hide back, so a long pinch keeps it on screen.
final class ZoomIndicatorView: UIVisualEffectView {

    private let label = UILabel()

    private var isShowing = false
    private var pendingHide: DispatchWorkItem?

    init() {
        super.init(effect: nil)

        isUserInteractionEnabled    = false
        accessibilityElementsHidden = true
        cornerConfiguration         = .capsule()
        label.alpha                 = 0

        label.font                                      = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        label.textColor                                 = .label
        label.textAlignment                             = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ZoomIndicatorView is built in code, not from a storyboard")
    }

    /// show(_:) sets the text, materializes the capsule if it is hidden and moves the hide to
    /// 0.8 s from now.
    func show(_ text: String) {
        if label.text != text {
            label.text = text
        }

        if !isShowing {
            isShowing = true

            UIView.animate(withDuration: 0.2) {
                self.effect      = UIGlassEffect()
                self.label.alpha = 1
            }
        }

        pendingHide?.cancel()

        let hide = DispatchWorkItem { [weak self] in self?.hide() }
        pendingHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: hide)
    }

    private func hide() {
        isShowing = false

        UIView.animate(withDuration: 0.35) {
            self.effect      = nil
            self.label.alpha = 0
        }
    }
}
