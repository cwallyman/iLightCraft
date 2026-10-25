//
//  HistogramEasingTests.swift
//  iLightCraftTests
//

import Foundation
import Testing
@testable import iLightCraft

/// HistogramEasingTests covers the histogram's glide: it moves part of the way per time constant,
/// lands exactly on the target and stops, bends toward a new target mid-glide, and jumps at once
/// for the first histogram, under Reduce Motion and when the photo goes away.
struct HistogramEasingTests {

    /// histogram has `count` pixels in red bin 128 and nothing else.
    private func histogram(count: UInt32) -> FrameHistogram {
        var red = [UInt32](repeating: 0, count: 256)
        red[128] = count

        let flat = [UInt32](repeating: 0, count: 256)

        return FrameHistogram(
            red         : red,
            green       : flat,
            blue        : flat,
            luma        : flat,
            total       : Int(count),
            clippedLow  : [0, 0, 0],
            clippedHigh : [0, 0, 0],
            generation  : 1,
            isDraft     : true
        )
    }

    /// easing shows 100 pixels in bin 128 (height 10), then aims at 400 (height 20) at time 0.
    private func easingTowardTwenty(instantly: Bool = false) -> HistogramEasing {
        var easing = HistogramEasing()
        easing.retarget(to: histogram(count: 100), at: 0, instantly: false)
        easing.retarget(to: histogram(count: 400), at: 0, instantly: instantly)
        return easing
    }

    @Test
    func theFirstHistogramShowsAtOnce() {
        var easing = HistogramEasing()
        easing.retarget(to: histogram(count: 100), at: 0, instantly: false)

        #expect(!easing.isMoving)
        #expect(easing.levels[128] == 10)
        #expect(easing.levels.count == 4 * HistogramEasing.binCount)
    }

    /// After one time constant the height has gone 63 % of the way, as an exponential approach does.
    @Test
    func oneTimeConstantGoesMostOfTheWay() {
        var easing = easingTowardTwenty()

        easing.advance(to: HistogramEasing.timeConstant)

        #expect(easing.isMoving)
        #expect(abs(easing.levels[128] - (20 - 10 * Float(exp(-1.0)))) < 0.001)
    }

    /// At 60 Hz the glide lands exactly on the target within half a second and then stays still.
    @Test
    func theGlideConvergesAndStops() {
        var easing = easingTowardTwenty()
        var ticks  = 0

        while easing.isMoving, ticks < 30 {
            ticks += 1
            easing.advance(to: Double(ticks) / 60)
        }

        #expect(!easing.isMoving)
        #expect(easing.levels[128] == 20)

        let resting = easing
        easing.advance(to: 10)

        #expect(easing == resting)
    }

    /// A new target mid-glide keeps the clock and the height reached, and bends toward it.
    @Test
    func aNewTargetBendsTheGlide() {
        var easing = easingTowardTwenty()

        easing.advance(to: 0.05)
        let reached = easing.levels[128]

        easing.retarget(to: histogram(count: 25), at: 0.05, instantly: false)
        easing.advance(to: 0.06)

        #expect(easing.isMoving)
        #expect(easing.levels[128] < reached)
        #expect(easing.levels[128] > 5)
    }

    @Test
    func reduceMotionShowsEachHistogramAtOnce() {
        let easing = easingTowardTwenty(instantly: true)

        #expect(!easing.isMoving)
        #expect(easing.levels[128] == 20)
    }

    @Test
    func noHistogramEmptiesThePlot() {
        var easing = easingTowardTwenty()

        easing.retarget(to: nil, at: 0, instantly: false)

        #expect(!easing.isMoving)
        #expect(easing.levels.isEmpty)
    }
}
