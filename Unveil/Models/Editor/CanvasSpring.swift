//
//  CanvasSpring.swift
//  Unveil
//

import Foundation

/// CanvasSpring animates the canvas from one transform to another with a critically damped
/// spring: the fastest motion that never overshoots its target, so the image glides in and stops.
///
/// It is a closed-form value, not a simulation: `transform(at:)` is a pure function of the time
/// since the start, so a dropped display frame costs nothing and the animation cannot drift. Each
/// component (the zoom's logarithm, the offset's x and y) follows
/// `x(t) = target + (x0 + (v0 + w * x0) * t) * exp(-w * t)`, with `x0 = start - target`.
/// The zoom moves in log space so that zooming 1x to 4x feels as even as 4x to 16x.
///
/// The same spring does momentum. A flick starts at the finger's velocity toward a target
/// projected half a second ahead (what UIScrollView's normal deceleration would travel); with
/// `w = 2 / 0.5` the spring's pull and its damping cancel at the start, so the image leaves the
/// finger at the finger's speed and only slows down. If the target was clamped to an edge, the
/// same spring stops the image there sooner.
nonisolated struct CanvasSpring: Sendable {

    /// momentumProjection is how far ahead, in seconds of velocity, a flick lands.
    static let momentumProjection = 0.5

    /// momentumFrequency makes the spring's initial acceleration zero for a projected target.
    static let momentumFrequency  = 2 / momentumProjection

    /// snapFrequency is for the double tap and the rubber band: settled in about half a second.
    static let snapFrequency      = 11.0

    /// releaseVelocity(_:isPointer:) is the velocity a released pan hands to its glide: the finger's
    /// own, but none for a mouse or trackpad drag, whose release speed is the hand's, far above
    /// a finger's, and which stops where it is let go in every desktop editor.
    static func releaseVelocity(_ velocity: SIMD2<Double>, isPointer: Bool) -> SIMD2<Double> {
        isPointer ? .zero : velocity
    }

    /// scrollGlideDamping scales a trackpad scroll's release velocity: a two-finger swipe lifts at
    /// a speed that would throw the image far with a finger's glide.
    static let scrollGlideDamping = 0.5

    /// scrollReleaseVelocity(_:) is the velocity a released trackpad or wheel scroll hands to its glide.
    static func scrollReleaseVelocity(_ velocity: SIMD2<Double>) -> SIMD2<Double> {
        velocity * scrollGlideDamping
    }

    let start          : CanvasTransform
    let target         : CanvasTransform
    let offsetVelocity : SIMD2<Double>
    let frequency      : Double

    init(
        from start     : CanvasTransform,
        to target      : CanvasTransform,
        offsetVelocity : SIMD2<Double> = .zero,
        frequency      : Double = CanvasSpring.snapFrequency
    ) {
        self.start          = start
        self.target         = target
        self.offsetVelocity = offsetVelocity
        self.frequency      = frequency
    }

    /// transform(at:) is the canvas `elapsed` seconds after the start; past the settle point
    /// it is exactly `target`.
    func transform(at elapsed: Double) -> CanvasTransform {
        guard !isSettled(at: elapsed) else { return target }

        let (zoomGap, offsetGap) = gaps(at: elapsed)

        return CanvasTransform(
            zoom   : exp(log(target.zoom) + zoomGap),
            offset : target.offset + offsetGap
        )
    }

    /// isSettled(at:) is true once every component is within a tenth of a point (or a
    /// hundredth of a percent of zoom) of the target, too little to see.
    func isSettled(at elapsed: Double) -> Bool {
        guard elapsed > 0 else { return start == target }

        let (zoomGap, offsetGap) = gaps(at: elapsed)

        return abs(zoomGap) < 1e-4 && abs(offsetGap.x) < 0.1 && abs(offsetGap.y) < 0.1
    }

    /// gaps returns how far each component still is from the target at `elapsed`.
    private func gaps(at elapsed: Double) -> (zoom: Double, offset: SIMD2<Double>) {
        let decay      = exp(-frequency * elapsed)
        let zoomStart  = log(start.zoom) - log(target.zoom)
        let offsetGap0 = start.offset - target.offset
        let zoomGap    = zoomStart * (1 + frequency * elapsed) * decay
        let offsetGap  = (offsetGap0 + (offsetVelocity + frequency * offsetGap0) * elapsed) * decay

        return (zoomGap, offsetGap)
    }
}
