//
//  FloatingCardsView.swift
//  Unveil
//

import CoreImage
import UIKit

/// FloatingCardsView draws the home's five photo cards and floats them entirely in Core Animation.
///
/// Each card is two layers: a holder at the card's place in the upper half, which drifts with
/// additive `position` animations and gives its child a perspective, and the card itself, which
/// tilts by animating its 3D `transform` and draws a pre-rendered image with an explicit
/// `shadowPath`. The animations repeat forever and autoreverse, so once added the render server
/// runs them and the main thread does no work at all while the cards float.
///
/// Depth sets each card's look (scale, blur, dimming, shadow) and its motion (FloatingCardMotion).
/// Blur, dimming and the rounded corners are baked into each card's image once, off the main
/// thread, at its displayed pixel size: nothing is filtered per frame. `isMoving` pauses the tree
/// by freezing its time (the cards stay where they are) and resumes it from there; `isAnimated`
/// false (Reduce Motion) adds no animations at all. Core Animation drops animations while the app
/// is in the background, so becoming active again re-adds whatever is missing. Every animation,
/// first or re-added, begins at the same `motionOrigin` on the tree's clock, which only runs
/// while the cards move, so a re-added animation resumes the pose the cards were paused in.
final class FloatingCardsView: UIView {

    var isMoving: Bool = false {
        didSet { updateMotion() }
    }

    var isAnimated: Bool = true {
        didSet { updateMotion() }
    }

    private let cardsLayer = CALayer()
    private var holders    : [CALayer] = []
    private var cardLayers : [CALayer] = []

    private var hasStartedRendering = false
    private var motionOrigin        : CFTimeInterval?

    override init(frame: CGRect) {
        super.init(frame: frame)

        isUserInteractionEnabled = false
        layer.addSublayer(cardsLayer)

        for card in Self.cards {
            let holder    = CALayer()
            let cardLayer = CALayer()

            cardLayer.transform     = Self.tiltTransform(card: card, degrees: card.tilt)
            cardLayer.shadowColor   = UIColor.black.cgColor
            cardLayer.shadowOpacity = Float(0.35 + card.nearness * 0.3)
            cardLayer.shadowRadius  = (8 + card.nearness * 26) * card.scale
            cardLayer.shadowOffset  = CGSize(width: 0, height: (6 + card.nearness * 18) * card.scale)

            holder.addSublayer(cardLayer)
            cardsLayer.addSublayer(holder)

            holders.append(holder)
            cardLayers.append(cardLayer)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FloatingCardsView is built in code, not from a storyboard")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let upperHalf = CGSize(width: bounds.width, height: bounds.height / 2)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        cardsLayer.frame = bounds
        for (holder, card) in zip(holders, Self.cards) {
            holder.position = CGPoint(
                x: upperHalf.width * card.position.x,
                y: upperHalf.height * card.position.y
            )
        }

        CATransaction.commit()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        guard window != nil, !hasStartedRendering else { return }

        hasStartedRendering = true
        renderCards(displayScale: traitCollection.displayScale)
    }

    // MARK: - Motion

    /// updateMotion makes the layer tree match the two flags: no animations under Reduce Motion,
    /// otherwise every animation present (re-added if Core Animation dropped them) and the tree's
    /// clock running only while the cards should move.
    private func updateMotion() {
        guard isAnimated else {
            holders.forEach { $0.removeAllAnimations() }
            cardLayers.forEach { $0.removeAllAnimations() }
            resume()
            return
        }

        if cardLayers.contains(where: { $0.animationKeys() == nil }) {
            addAnimations()
        }

        if isMoving {
            resume()
        } else {
            pause()
        }
    }

    /// addAnimations (re)adds every card's animations, all beginning at `motionOrigin`, the
    /// tree's time when they were first added. The tree's clock froze while paused and skips the
    /// paused time on resume, so a re-added animation lands on the pose the cards last showed.
    private func addAnimations() {
        let origin = motionOrigin ?? cardsLayer.convertTime(CACurrentMediaTime(), from: nil)
        motionOrigin = origin

        for (index, card) in Self.cards.enumerated() {
            let motion    = card.motion
            let holder    = holders[index]
            let cardLayer = cardLayers[index]

            holder.removeAllAnimations()
            cardLayer.removeAllAnimations()

            holder.add(
                Self.swing(
                    keyPath    : "position.x",
                    from       : -motion.driftX,
                    to         : motion.driftX,
                    period     : motion.periodX,
                    beginTime  : origin,
                    timeOffset : motion.timeOffsetX,
                    isAdditive : true
                ),
                forKey: "driftX"
            )

            holder.add(
                Self.swing(
                    keyPath    : "position.y",
                    from       : -motion.driftY,
                    to         : motion.driftY,
                    period     : motion.periodY,
                    beginTime  : origin,
                    timeOffset : motion.timeOffsetY,
                    isAdditive : true
                ),
                forKey: "driftY"
            )

            let leastTilt = Self.tiltTransform(card: card, degrees: card.tilt - motion.tiltDegrees)
            let mostTilt  = Self.tiltTransform(card: card, degrees: card.tilt + motion.tiltDegrees)

            cardLayer.add(
                Self.swing(
                    keyPath    : "transform",
                    from       : NSValue(caTransform3D: leastTilt),
                    to         : NSValue(caTransform3D: mostTilt),
                    period     : motion.periodTilt,
                    beginTime  : origin,
                    timeOffset : motion.timeOffsetTilt,
                    isAdditive : false
                ),
                forKey: "tilt"
            )
        }
    }

    /// pause freezes the tree's clock at the current instant, so every card holds its frame.
    private func pause() {
        guard cardsLayer.speed != 0 else { return }

        let now = cardsLayer.convertTime(CACurrentMediaTime(), from: nil)
        cardsLayer.speed      = 0
        cardsLayer.timeOffset = now
    }

    /// resume restarts the clock from the frozen instant: the time spent paused is skipped, not
    /// replayed, so the cards continue from exactly where they stopped.
    private func resume() {
        guard cardsLayer.speed == 0 else { return }

        let pausedTime = cardsLayer.timeOffset
        cardsLayer.speed      = 1
        cardsLayer.timeOffset = 0
        cardsLayer.beginTime  = 0
        cardsLayer.beginTime  = cardsLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
    }

    /// swing is one autoreversing, endlessly repeating ease in out between two values. A period
    /// is the full cycle, so one leg lasts half of it; `timeOffset` sets where in it the card starts
    /// and `beginTime` (on the tree's clock) when that start was.
    private static func swing(
        keyPath   : String,
        from      : Any,
        to        : Any,
        period    : Double,
        beginTime : CFTimeInterval,
        timeOffset: Double,
        isAdditive: Bool
    ) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue      = from
        animation.toValue        = to
        animation.isAdditive     = isAdditive
        animation.duration       = period / 2
        animation.autoreverses   = true
        animation.repeatCount    = .infinity
        animation.beginTime      = beginTime
        animation.timeOffset     = timeOffset
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }

    /// tiltTransform turns the card around a mostly vertical axis (the perspective comes from the
    /// holder's `sublayerTransform`), then leans it in plane by a third of its resting tilt.
    private static func tiltTransform(
        card   : Card,
        degrees: Double
    ) -> CATransform3D {
        let turn = CATransform3DMakeRotation(degrees * .pi / 180, 0.25, 1, 0)
        let lean = CATransform3DMakeRotation(card.tilt * 0.3 * .pi / 180, 0, 0, 1)

        return CATransform3DConcat(turn, lean)
    }

    // MARK: - Images

    /// renderCards bakes every card's image off the main thread and hands the results back to
    /// the layers. It runs once, the first time the view is in a window and knows its scale.
    private func renderCards(displayScale: CGFloat) {
        let cards = Self.cards

        Task.detached(priority: .userInitiated) { [weak self] in
            let images = cards.map { Self.renderImage(for: $0, displayScale: displayScale) }

            await self?.apply(images)
        }
    }

    private func apply(_ images: [RenderedCard?]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for (index, rendered) in images.enumerated() {
            guard let rendered else { continue }

            let card      = Self.cards[index]
            let cardLayer = cardLayers[index]
            let bounds    = CGRect(origin: .zero, size: rendered.size)

            cardLayer.bounds     = bounds
            cardLayer.contents   = rendered.image
            cardLayer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: card.cornerRadius).cgPath

            // The same relative vanishing point as the old rotation3DEffect(perspective: 0.6).
            var perspective = CATransform3DIdentity
            perspective.m34 = -0.6 / max(bounds.width, bounds.height)
            holders[index].sublayerTransform = perspective
        }

        CATransaction.commit()
    }

    /// renderImage draws one card at its displayed pixel size: the photo blurred by its depth,
    /// clipped to the rounded rectangle and dimmed with black. Nil if the asset cannot be read.
    nonisolated private static func renderImage(
        for card    : Card,
        displayScale: CGFloat
    ) -> RenderedCard? {
        guard let photo  = UIImage(named: card.imageName),
              let source = photo.cgImage,
              photo.size.width > 0
        else {
            return nil
        }

        let width       = card.width * card.scale
        let size        = CGSize(width: width, height: width * photo.size.height / photo.size.width)
        let sourceScale = CGFloat(source.width) / size.width
        let blurred     = blur(source, sigma: card.blurRadius * sourceScale) ?? source

        let format = UIGraphicsImageRendererFormat()
        format.scale  = displayScale
        format.opaque = false

        let rect  = CGRect(origin: .zero, size: size)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIBezierPath(roundedRect: rect, cornerRadius: card.cornerRadius).addClip()
            UIImage(cgImage: blurred).draw(in: rect)

            // fill(_:) alone copies the color over the photo; the dimming must blend.
            UIColor.black.withAlphaComponent(card.dimming).setFill()
            context.fill(rect, blendMode: .normal)
        }

        guard let cgImage = image.cgImage else { return nil }

        return RenderedCard(image: cgImage, size: size)
    }

    /// blur applies a Gaussian blur with clamped edges, so the card keeps a crisp outline.
    nonisolated private static func blur(
        _ image: CGImage,
        sigma  : CGFloat
    ) -> CGImage? {
        guard sigma > 0.5 else { return image }

        let input  = CIImage(cgImage: image)
        let output = input
            .clampedToExtent()
            .applyingGaussianBlur(sigma: Double(sigma))
            .cropped(to: input.extent)

        return blurContext.createCGImage(output, from: input.extent)
    }

    nonisolated private static let blurContext = CIContext()

    // MARK: - Cards

    nonisolated private struct RenderedCard: Sendable {

        let image: CGImage
        let size : CGSize
    }

    /// Card places one photo in the upper half: position as a fraction of that area, its width
    /// at depth 0, depth from 0 (nearest) to 1 (farthest), resting tilt and motion phase. The
    /// rest of its look follows from depth.
    nonisolated private struct Card: Sendable {

        let imageName: String
        let position : CGPoint
        let width    : CGFloat
        let depth    : Double
        let tilt     : Double
        let phase    : Double

        var nearness    : Double  { 1 - depth }
        var scale       : CGFloat { 0.6 + nearness * 0.4 }
        var cornerRadius: CGFloat { 18 * scale }
        var blurRadius  : CGFloat { depth * 5 * scale }
        var dimming     : CGFloat { depth * 0.25 }
        var motion      : FloatingCardMotion { FloatingCardMotion(depth: depth, phase: phase) }
    }

    nonisolated private static let cards: [Card] = [
        Card(
            imageName : "HomeCard-Z7-14bit-lossless-L",
            position  : CGPoint(x: 0.30, y: 0.34),
            width     : 240,
            depth     : 0.85,
            tilt      : 10,
            phase     : 0.00
        ),
        Card(
            imageName : "HomeCard-iPhone12Pro_IMG_1361",
            position  : CGPoint(x: 0.71, y: 0.30),
            width     : 170,
            depth     : 0.70,
            tilt      : -12,
            phase     : 0.23
        ),
        Card(
            imageName : "HomeCard-Canon_EOS_R5_RAW_ISO_100_nocrop_nodual",
            position  : CGPoint(x: 0.52, y: 0.88),
            width     : 220,
            depth     : 0.95,
            tilt      : 4,
            phase     : 0.47
        ),
        Card(
            imageName : "HomeCard-DSCF0267",
            position  : CGPoint(x: 0.14, y: 0.62),
            width     : 300,
            depth     : 0.10,
            tilt      : 16,
            phase     : 0.68
        ),
        Card(
            imageName : "HomeCard-ILCE-7M4_DSC06674_LossLess-Large",
            position  : CGPoint(x: 0.86, y: 0.60),
            width     : 300,
            depth     : 0.00,
            tilt      : -18,
            phase     : 0.89
        ),
    ]
}
