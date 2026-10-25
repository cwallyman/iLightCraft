//
//  DroppedFrameRetriesTests.swift
//  iLightCraftTests
//

import Testing
@testable import iLightCraft

struct DroppedFrameRetriesTests {

    /// answers feeds `outcomes` (dropped, milliseconds after the start) to a fresh rule with a
    /// one second limit and returns each answer.
    private func answers(_ outcomes: [(isDropped: Bool, milliseconds: Int)]) -> [Bool] {
        let start   = ContinuousClock.now
        var retries = DroppedFrameRetries(limit: .seconds(1))

        return outcomes.map {
            retries.shouldDrawAgain(isDropped: $0.isDropped, at: start + .milliseconds($0.milliseconds))
        }
    }

    @Test
    func aPresentedFrameNeverDrawsAgain() {
        #expect(answers([(false, 0)]) == [false])
    }

    /// The bound is a time: 120 drops in 0.99 s (more than a count of 30 allowed) all draw again,
    /// and the first one a second after the run began gives up.
    @Test
    func aDroppedFrameDrawsAgainForASecondThenGivesUp() {
        let run = (0 ..< 120).map { (isDropped: true, milliseconds: $0 * 990 / 119) }

        #expect(answers(run).allSatisfy { $0 })
        #expect(answers(run + [(true, 1000)]).last == false)
    }

    @Test
    func aPresentedFrameStartsTheTimeOver() {
        #expect(answers([(true, 0), (false, 900), (true, 1500), (true, 2400)]) == [true, false, true, true])
    }
}
