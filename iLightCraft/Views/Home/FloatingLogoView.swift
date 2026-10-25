//
//  FloatingLogoView.swift
//  iLightCraft
//

import UIKit

/// FloatingLogoView floats the existing winking lynx with a render-server layer animation.
/// The layer clock pauses while covered or inactive; Reduce Motion restores a still logo.
final class FloatingLogoView: UIView {

    var isMoving = false {
        didSet { updateMotion() }
    }

    var isAnimated = true {
        didSet { updateMotion() }
    }

    private let logo = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        logo.contents = UIImage(named: "iLightCraftLynx")?.cgImage
        logo.contentsGravity = .resizeAspect
        logo.masksToBounds = true
        logo.cornerCurve = .continuous
        layer.addSublayer(logo)
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.45
        layer.shadowRadius = 20
        layer.shadowOffset = CGSize(width: 0, height: 14)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        logo.frame = bounds
        logo.cornerRadius = bounds.width * 0.22
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: logo.cornerRadius).cgPath
        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateMotion()
    }

    /// updateMotion never starts a display link or a SwiftUI animation loop.
    private func updateMotion() {
        guard isAnimated else {
            logo.removeAllAnimations()
            logo.speed = 1
            logo.timeOffset = 0
            logo.beginTime = 0
            return
        }
        if logo.animation(forKey: "float") == nil {
            let float = CABasicAnimation(keyPath: "transform.translation.y")
            float.fromValue = -4
            float.toValue = 4
            float.duration = 4
            float.autoreverses = true
            float.repeatCount = .infinity
            float.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            logo.add(float, forKey: "float")
        }
        if isMoving && window != nil {
            guard logo.speed == 0 else { return }
            let paused = logo.timeOffset
            logo.speed = 1
            logo.timeOffset = 0
            logo.beginTime = 0
            logo.beginTime = logo.convertTime(CACurrentMediaTime(), from: nil) - paused
        } else if logo.speed != 0 {
            let paused = logo.convertTime(CACurrentMediaTime(), from: nil)
            logo.speed = 0
            logo.timeOffset = paused
        }
    }
}
