//
//  CanvasSpringTests.swift
//  UnveilTests
//

import simd
import Testing
@testable import Unveil

struct CanvasSpringTests {

    @Test
    func theSpringStartsAtTheStartAndEndsExactlyOnTheTarget() {
        let start  = CanvasTransform(zoom: 1, offset: .zero)
        let target = CanvasTransform(zoom: 4, offset: SIMD2(120, -40))
        let spring = CanvasSpring(from: start, to: target)

        let first = spring.transform(at: 0.0001)

        #expect(abs(first.zoom - 1) < 0.01 && abs(first.offset.x) < 0.5)
        #expect(spring.isSettled(at: 3))
        #expect(spring.transform(at: 3) == target)
    }

    @Test
    func aCriticallyDampedSpringNeverOvershoots() {
        let start  = CanvasTransform(zoom: 2, offset: .zero)
        let target = CanvasTransform(zoom: 2, offset: SIMD2(300, 0))
        let spring = CanvasSpring(from: start, to: target, offsetVelocity: SIMD2(600, 0), frequency: CanvasSpring.momentumFrequency)

        let samples = stride(from: 0.0, through: 3, by: 1.0 / 120).map { spring.transform(at: $0).offset.x }

        #expect(samples.allSatisfy { $0 <= 300.0001 })
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 + 1e-9 })
    }

    /// A scroll glide is the momentum spring sampled once per 60 Hz frame (F6): every frame moves,
    /// and each step is no longer than the one before, so no frame stalls or jumps double. The
    /// settle's last step (about 0.1 pt, see `isSettled`) is the only exception.
    @Test
    func aMomentumGlideMovesOnEveryFrameAndOnlySlowsDown() {
        let start  = CanvasTransform(zoom: 2, offset: .zero)
        let target = CanvasTransform(zoom: 2, offset: SIMD2(-600, 0))
        let spring = CanvasSpring(
            from           : start,
            to             : target,
            offsetVelocity : SIMD2(-1200, 0),
            frequency      : CanvasSpring.momentumFrequency
        )

        let frames  = stride(from: 0.0, through: 3, by: 1.0 / 60).map { spring.transform(at: $0).offset.x }
        let steps   = zip(frames, frames.dropFirst()).map { $0 - $1 }
        let moving  = steps.prefix { $0 > 0 }

        #expect(abs(steps[0] - 1200.0 / 60) < 1)
        #expect(moving.count > 60)
        #expect(zip(moving.dropLast(), moving.dropLast().dropFirst()).allSatisfy { $1 <= $0 + 1e-9 })
        #expect(moving.last.map { $0 < 0.2 } == true)
        #expect(steps.dropFirst(moving.count).allSatisfy { $0 == 0 })
    }

    /// A new spring starts on the frame before its first one, so the first frame moves one frame's
    /// worth (F6); after a sleeping display link it starts one refresh of that display back.
    @Test
    func aSpringStartsOnTheFrameBeforeItsFirst() {
        func start(_ firstFrame: Double, after previousFrame: Double, at hertz: Double) -> Double {
            CanvasSpring.startTime(
                firstFrame    : firstFrame,
                previousFrame : previousFrame,
                frameInterval : 1 / hertz
            )
        }

        #expect(start(10 + 1.0 / 120, after: 10, at: 120) == 10)
        #expect(start(10 + 1.0 / 60, after: 10, at: 60) == 10)
        #expect(abs(start(20, after: 10, at: 60) - (20 - 1.0 / 60)) < 1e-12)
        #expect(abs(start(20, after: 10, at: 120) - (20 - 1.0 / 120)) < 1e-12)
    }

    /// Glides from F6's recording (zoom 2.644, edges at x 970 and y 629.8), each axis's release
    /// offset and velocity fitted from the frames: one released 409 pt from the edge at 10,289 pt/s,
    /// two released past the edge in the rubber band still moving out. With the capped velocity
    /// every axis stays between where it was let go and where it rests: never past an edge, never
    /// further into the rubber band. The uncapped velocity overshot (up to 1007 pt measured).
    @Test(arguments: [
        (start: SIMD2(-702.6, -220.3), velocity: SIMD2(4409.0, -10289.0)),
        (start: SIMD2(-631.4, -788.6), velocity: SIMD2(-624.0, -11391.0)),
        (start: SIMD2(387.9, -801.6), velocity: SIMD2(-3018.0, -7028.0)),
    ])
    func aMomentumGlideNeverPassesAClampedEdge(start: SIMD2<Double>, velocity: SIMD2<Double>) {
        let edge     = SIMD2(970.0, 629.8)
        let target   = simd_clamp(start + velocity * CanvasSpring.momentumProjection, -edge, edge)
        let momentum = CanvasSpring.momentumVelocity(
            velocity,
            from : start,
            to   : target
        )

        func path(_ offsetVelocity: SIMD2<Double>) -> [SIMD2<Double>] {
            let spring = CanvasSpring(
                from           : CanvasTransform(zoom: 2.644, offset: start),
                to             : CanvasTransform(zoom: 2.644, offset: target),
                offsetVelocity : offsetVelocity,
                frequency      : CanvasSpring.momentumFrequency
            )

            return stride(from: 0.0, through: 4, by: 1.0 / 120).map { spring.transform(at: $0).offset }
        }

        func staysBetweenStartAndTarget(_ samples: [SIMD2<Double>]) -> Bool {
            let low  = simd_min(start, target) - 1e-9
            let high = simd_max(start, target) + 1e-9

            return samples.allSatisfy { all($0 .>= low) && all($0 .<= high) }
        }

        #expect(!staysBetweenStartAndTarget(path(velocity)))
        #expect(staysBetweenStartAndTarget(path(momentum)))
        #expect(path(momentum).last == target)
    }

    /// A glide that ends inside the image keeps its whole velocity (the cap has twice the room), so
    /// only clamped glides change; the velocity away from the target, or with no room, is dropped.
    @Test
    func theCapLeavesAFreeGlideAloneAndDropsMomentumWithNoRoom() {
        let velocity = SIMD2(1200.0, -800.0)
        let start    = SIMD2(10.0, 20.0)

        func capped(toward target: SIMD2<Double>) -> SIMD2<Double> {
            CanvasSpring.momentumVelocity(
                velocity,
                from : start,
                to   : target
            )
        }

        #expect(capped(toward: start + velocity * CanvasSpring.momentumProjection) == velocity)
        #expect(capped(toward: start) == .zero)
        #expect(capped(toward: start - velocity) == .zero)
        #expect(capped(toward: start + SIMD2(100, -50)) == SIMD2(400, -200))
    }
}
