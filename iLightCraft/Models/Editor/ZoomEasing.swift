//
//  ZoomEasing.swift
//  iLightCraft
//

import CoreGraphics
import Foundation

// nonisolated: a plain value, stepped by the canvas on each display update and by the tests.
/// ZoomEasing turns the coarse zoom steps of a trackpad pinch and of Cmd + scroll into continuous
/// motion. The device recording of F5 showed iPadOS delivering a trackpad pinch as about five
/// events per gesture, a median 9 % (up to 56 %) zoom apart and up to 38 ms apart: applied as they
/// come, the photo jumps in visible steps.
///
/// Each event adds its factor to the zoom still owed (`pending`, a natural logarithm) and moves the
/// anchor to the pointer. Each display update then applies part of what is owed, an exponential
/// approach with the time constant `timeConstant`, and the canvas zooms by that part about the
/// anchor through CanvasTransform.pinch, so the rubber band and the point under the pointer behave
/// as with a direct pinch. Once less than `tolerance` is owed the rest goes in one step and it is
/// idle. A finger pinch stays direct; under Reduce Motion the canvas applies each event at once.
nonisolated struct ZoomEasing: Equatable, Sendable {

    /// timeConstant is the calibration knob of the glide, in seconds: short enough to feel attached
    /// to the fingers (a 40 ms step is 63 % shown after 45 ms), long enough to bridge the events.
    static let timeConstant = 0.045

    /// tolerance is the owed zoom, as a logarithm, below which the rest is applied at once (0.1 %).
    static let tolerance = 0.001

    /// longestStep caps one step, so a display link that resumes after a pause does not leap.
    static let longestStep = 0.1

    private(set) var pending: Double  = 0
    private(set) var anchor : CGPoint = .zero

    var isIdle: Bool {
        pending == 0
    }

    /// add owes the zoom `factor` more, about `point`. A non-finite or non-positive factor is ignored.
    mutating func add(_ factor: Double, around point: CGPoint) {
        guard factor.isFinite, factor > 0 else { return }

        pending += log(factor)
        anchor   = point
    }

    /// step takes the part of the owed zoom due after `elapsed` seconds and returns it as a factor
    /// (1 when idle).
    mutating func step(elapsed: Double) -> Double {
        guard !isIdle else { return 1 }

        let pull = 1 - exp(-min(max(elapsed, 0), Self.longestStep) / Self.timeConstant)
        var take = pending * pull

        if abs(pending - take) < Self.tolerance {
            take = pending
        }

        pending -= take

        return exp(take)
    }

    /// reset forgets the owed zoom: another gesture or a spring took over.
    mutating func reset() {
        pending = 0
    }
}
