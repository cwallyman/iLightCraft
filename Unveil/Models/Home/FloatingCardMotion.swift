//
//  FloatingCardMotion.swift
//  Unveil
//

import Foundation

/// FloatingCardMotion is how one home card floats, derived from its depth (0 nearest, 1 farthest)
/// and its phase (0 to 1, a fraction of each cycle).
///
/// The motion is meant to be barely perceptible: a few points of drift, about a degree of tilt,
/// cycles of 14 to 22 seconds. Nearer cards drift farther, tilt more and cycle a little faster
/// than far ones, which is what makes the five read as parallax layers of one scene. Each axis
/// has its own period, so a card traces a slow Lissajous loop instead of a line, and the phase
/// staggers the cards so they never move in step. Periods are full cycles (there and back);
/// amplitudes are measured from the rest pose.
nonisolated struct FloatingCardMotion: Equatable, Sendable {

    let driftX        : Double   // Points either side of the rest position.
    let driftY        : Double
    let tiltDegrees   : Double   // Degrees either side of the card's resting tilt.
    let periodX       : Double   // Seconds per full cycle.
    let periodY       : Double
    let periodTilt    : Double
    let timeOffsetX   : Double   // Seconds into each cycle at which the card starts.
    let timeOffsetY   : Double
    let timeOffsetTilt: Double

    init(
        depth: Double,
        phase: Double
    ) {
        let depth    = min(max(depth, 0), 1)
        let nearness = 1 - depth

        driftX         = 3 + 5 * nearness
        driftY         = driftX * 0.6
        tiltDegrees    = 0.5 + nearness
        periodX        = 14 + 6 * depth
        periodY        = periodX + 2
        periodTilt     = periodX + 1
        timeOffsetX    = Self.offset(phase: phase, period: periodX)
        timeOffsetY    = Self.offset(phase: phase + 0.37, period: periodY)
        timeOffsetTilt = Self.offset(phase: phase + 0.61, period: periodTilt)
    }

    /// offset turns a phase into seconds within one full cycle, wrapping phases past 1.
    private static func offset(
        phase : Double,
        period: Double
    ) -> Double {
        let wrapped = phase - phase.rounded(.down)

        return wrapped * period
    }
}
