//
//  HistogramEasing.swift
//  Unveil
//

import Foundation

// nonisolated: a plain value, stepped by the histogram view and by the tests.
/// HistogramEasing is the histogram the adjust card shows while it glides toward the newest one.
///
/// It keeps the plotted heights, the square roots of the bin counts (red, green, blue, then
/// luminance, `binCount` each), and moves every one of them toward the target by an exponential
/// approach with the time constant `timeConstant`: after one time constant 63 % of the way, after
/// three 95 %. A new target mid-glide just bends the motion, so a drag's drafts and the slightly
/// different full preview that settles a release glide instead of jumping. Easing the square roots,
/// which is what the plot draws, makes the motion uniform on screen whatever the counts.
///
/// Once no height is farther from its target than `tolerance` of the target's peak (sub-pixel for
/// any card), it snaps there and stops: `isMoving` false is what pauses the view's timeline, so a
/// converged plot never animates. The first histogram, and every one under Reduce Motion, is shown
/// at once.
nonisolated struct HistogramEasing: Equatable, Sendable {

    static let binCount     = 256
    static let timeConstant = 0.07
    static let tolerance    : Float = 0.002

    /// longestStep caps one step, so a timeline that resumes after a pause does not leap.
    static let longestStep = 0.1

    /// levels are the shown heights (see the type doc); empty when there is no histogram.
    private(set) var levels  : [Float] = []
    private(set) var isMoving: Bool = false

    private var target       : [Float] = []
    private var lastTime     : Double = 0
    private var stopDistance : Float = 0

    /// retarget(to:at:instantly:) aims at `histogram` from `time` (seconds, the clock `advance` is
    /// given). With no histogram the plot empties; the first one, or any with `instantly`, is shown
    /// at once.
    mutating func retarget(to histogram: FrameHistogram?, at time: Double, instantly: Bool) {
        guard let histogram else {
            levels   = []
            target   = []
            isMoving = false
            return
        }

        target       = [histogram.red, histogram.green, histogram.blue, histogram.luma].flatMap { bins in
            bins.map { Float($0).squareRoot() }
        }
        stopDistance = Self.tolerance * max(Self.peak(of: target), 1)

        guard !instantly, levels.count == target.count, levels != target else {
            levels   = target
            isMoving = false
            return
        }

        // A glide in progress keeps its clock, so a new draft does not stall it for a frame.
        if !isMoving {
            lastTime = time
        }

        isMoving = true
    }

    /// advance moves every height toward the target for the time since the last step, and stops
    /// exactly on it once all are within the stop distance (see the type doc).
    mutating func advance(to time: Double) {
        guard isMoving else { return }

        let step = min(max(time - lastTime, 0), Self.longestStep)
        let pull = Float(1 - exp(-step / Self.timeConstant))
        var farthest: Float = 0

        lastTime = time

        for index in levels.indices {
            levels[index] += (target[index] - levels[index]) * pull
            farthest = max(farthest, abs(target[index] - levels[index]))
        }

        if farthest <= stopDistance {
            levels   = target
            isMoving = false
        }
    }

    /// peak is the tallest height of any channel away from the two ends (see HistogramView), at
    /// least 1 so an empty plot divides safely.
    static func peak(of levels: [Float]) -> Float {
        var peak: Float = 1

        for channel in 0 ..< levels.count / binCount {
            let start = channel * binCount

            for index in start + 1 ..< start + binCount - 1 {
                peak = max(peak, levels[index])
            }
        }

        return peak
    }
}
