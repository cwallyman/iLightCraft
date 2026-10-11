//
//  FloatingCardsTests.swift
//  UnveilTests
//

import QuartzCore
import Testing
import UIKit
@testable import Unveil

struct FloatingCardsTests {

    @Test
    func depthSetsDriftTiltAndPeriodWithinTheirRanges() {
        let nearest  = FloatingCardMotion(depth: 0, phase: 0)
        let farthest = FloatingCardMotion(depth: 1, phase: 0)

        #expect(nearest.driftX == 8 && farthest.driftX == 3)
        #expect(nearest.tiltDegrees == 1.5 && farthest.tiltDegrees == 0.5)
        #expect(nearest.periodX == 14 && farthest.periodX == 20)

        for depth in stride(from: 0.0, through: 1, by: 0.05) {
            let motion = FloatingCardMotion(depth: depth, phase: 0.5)

            #expect((3...8).contains(motion.driftX) && motion.driftY <= motion.driftX)
            #expect((0.5...1.5).contains(motion.tiltDegrees))
            #expect([motion.periodX, motion.periodY, motion.periodTilt].allSatisfy { (14...22).contains($0) })
        }
    }

    @Test
    func nearerCardsMoveMoreAndFaster() {
        let near = FloatingCardMotion(depth: 0.2, phase: 0)
        let far  = FloatingCardMotion(depth: 0.8, phase: 0)

        #expect(near.driftX > far.driftX && near.driftY > far.driftY)
        #expect(near.tiltDegrees > far.tiltDegrees)
        #expect(near.periodX < far.periodX)
    }

    @Test
    func phaseStaggersTheCardsWithinOneCycle() {
        let start = FloatingCardMotion(depth: 0.5, phase: 0)
        let later = FloatingCardMotion(depth: 0.5, phase: 0.25)
        let wrap  = FloatingCardMotion(depth: 0.5, phase: 1.25)

        #expect(start.timeOffsetX == 0)
        #expect(later.timeOffsetX == later.periodX * 0.25)
        #expect(abs(wrap.timeOffsetX - later.timeOffsetX) < 1e-9)
        #expect([later.timeOffsetY, later.timeOffsetTilt].allSatisfy { $0 >= 0 })
        #expect(later.timeOffsetY < later.periodY && later.timeOffsetTilt < later.periodTilt)
    }

    @Test
    @MainActor
    func theCardsFloatInCoreAnimationPauseInPlaceAndStayStillUnderReduceMotion() throws {
        let view    = FloatingCardsView()
        let cards   = try #require(view.layer.sublayers?.first)
        let holders = try #require(cards.sublayers)

        view.isMoving = true

        let drift = try #require(holders.first?.animation(forKey: "driftX") as? CABasicAnimation)
        #expect(holders.count == 5)
        #expect(holders.allSatisfy { $0.animationKeys()?.sorted() == ["driftX", "driftY"] })
        #expect(holders.allSatisfy { $0.sublayers?.first?.animation(forKey: "tilt") != nil })
        #expect(drift.autoreverses && drift.repeatCount == .infinity && drift.isAdditive)
        #expect(cards.speed == 1)

        view.isMoving = false
        #expect(cards.speed == 0)
        #expect(holders.allSatisfy { $0.animationKeys() != nil })

        view.isMoving = true
        #expect(cards.speed == 1)

        let still        = FloatingCardsView()
        let stillHolders = try #require(still.layer.sublayers?.first?.sublayers)
        still.isAnimated = false
        still.isMoving   = true
        #expect(stillHolders.allSatisfy { $0.animationKeys() == nil })
    }

    /// animationsReAddedAfterTheBackgroundResumeThePausedPose drops every animation while paused,
    /// as the background does, then resumes. The re-added animations must begin where the first
    /// ones did on the tree's frozen clock, so each card's animation time, and pose, is unchanged.
    @Test
    @MainActor
    func animationsReAddedAfterTheBackgroundResumeThePausedPose() throws {
        let view    = FloatingCardsView()
        let cards   = try #require(view.layer.sublayers?.first)
        let holders = try #require(cards.sublayers)

        view.isMoving = true
        let firstBegin = try #require(holders.first?.animation(forKey: "driftX")?.beginTime)

        view.isMoving = false
        for holder in holders {
            holder.removeAllAnimations()
            holder.sublayers?.forEach { $0.removeAllAnimations() }
        }
        view.isMoving = true

        #expect(firstBegin != 0)
        #expect(holders.allSatisfy { $0.animation(forKey: "driftX")?.beginTime == firstBegin })
        #expect(holders.allSatisfy { $0.sublayers?.first?.animation(forKey: "tilt")?.beginTime == firstBegin })
        #expect(cards.speed == 1)
    }
}
