//
//  HomePanelGeometryTests.swift
//  UnveilTests
//

import CoreGraphics
import Testing
@testable import Unveil

struct HomePanelGeometryTests {

    private let geometry = HomePanelGeometry(travel: 400)

    @Test
    func aSlowReleaseSettlesOnTheNearerDetent() {
        #expect(!geometry.settlesExpanded(isExpanded: false, translation: -150, velocity: 0))
        #expect(geometry.settlesExpanded(isExpanded: false, translation: -250, velocity: 0))
        #expect(geometry.settlesExpanded(isExpanded: true, translation: 150, velocity: 0))
        #expect(!geometry.settlesExpanded(isExpanded: true, translation: 250, velocity: 0))
    }

    @Test
    func aShortFlickChangesState() {
        #expect(geometry.settlesExpanded(isExpanded: false, translation: -40, velocity: -1000))
        #expect(!geometry.settlesExpanded(isExpanded: true, translation: 40, velocity: 1000))
    }

    @Test
    func aFlickAgainstAFarDragWins() {
        #expect(!geometry.settlesExpanded(isExpanded: false, translation: -300, velocity: 1200))
        #expect(geometry.settlesExpanded(isExpanded: true, translation: 300, velocity: -1200))
    }

    @Test
    func theFingerIsFollowedOneToOneInsideTheRange() {
        #expect(geometry.offset(isExpanded: false, translation: 0) == 400)
        #expect(geometry.offset(isExpanded: false, translation: -123) == 277)
        #expect(geometry.offset(isExpanded: true, translation: 0) == 0)
        #expect(geometry.offset(isExpanded: true, translation: 321) == 321)
    }

    @Test
    func pastEitherEndThePanelIsRubberBandedAndBounded() {
        let aboveTop    = geometry.offset(isExpanded: true, translation: -100)
        let belowBottom = geometry.offset(isExpanded: false, translation: 100)
        let farAbove    = geometry.offset(isExpanded: true, translation: -100_000)

        #expect(aboveTop < 0 && aboveTop > -50)
        #expect(belowBottom > 400 && belowBottom < 450)
        #expect(farAbove > -HomePanelGeometry.rubberBandLimit)
        #expect(geometry.offset(isExpanded: true, translation: -200) < aboveTop)
    }

    @Test
    func theSnapStartsAtTheReleaseSpeedWithoutOvershooting() {
        let frequency = 2 * Double.pi / HomePanelGeometry.snapDuration

        #expect(geometry.snapVelocity(from: 300, to: 0, velocity: -600) == 2)
        #expect(geometry.snapVelocity(from: 300, to: 0, velocity: -100_000) == frequency)
        #expect(geometry.snapVelocity(from: 300, to: 0, velocity: 100_000) == -frequency)
        #expect(geometry.snapVelocity(from: 0.5, to: 0, velocity: -600) == 0)
    }
}
