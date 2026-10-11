//
//  AdjustSliderModelTests.swift
//  UnveilTests
//

import CoreGraphics
import Testing
@testable import Unveil

/// AdjustSliderModelTests covers the pure parts of the adjust card: speed bands, fill geometry,
/// snapping to the step and the carousel's page logic.
struct AdjustSliderModelTests {

    @Test
    func speedBandsChangeEvery44PointsAndBoundariesAreSlower() {
        #expect(SliderSpeed(distance: 0)     == .full)
        #expect(SliderSpeed(distance: 43.9)  == .full)
        #expect(SliderSpeed(distance: 44)    == .half)
        #expect(SliderSpeed(distance: -60)   == .half)
        #expect(SliderSpeed(distance: 88)    == .quarter)
        #expect(SliderSpeed(distance: 131.9) == .quarter)
        #expect(SliderSpeed(distance: 132)   == .fine)
        #expect(SliderSpeed(distance: 900)   == .fine)

        #expect(SliderSpeed.allCases.map(\.factor) == [1, 0.5, 0.25, 0.125])
        #expect(SliderSpeed.allCases.map(\.label) == [nil, "Half Speed", "Quarter Speed", "Fine"])
    }

    @Test
    func centredControlsFillFromTheDefaultTowardTheThumb() {
        let range = -100.0 ... 100

        #expect(fractions(0, range, 0)   == [0.5, 0.5, 0.5])
        #expect(fractions(50, range, 0)  == [0.5, 0.75, 0.75])
        #expect(fractions(-50, range, 0) == [0.25, 0.5, 0.25])
    }

    /// A raw's as-shot Tint is the fill's origin, not the constant 0.
    @Test
    func aCentredFillStartsAtThePhotosOwnDefault() {
        #expect(fractions(0, -150 ... 150, 30) == [0.5, 0.6, 0.5])
    }

    @Test
    func otherControlsFillFromTheLowerBound() {
        #expect(fractions(75, 0 ... 150, 40)          == [0, 0.5, 0.5])
        #expect(fractions(2000, 2000 ... 50000, 5200) == [0, 0, 0])
    }

    @Test
    func aValueOutsideTheRangeIsClampedToTheTrack() {
        #expect(fractions(300, -100 ... 100, 0) == [0.5, 1, 1])
        #expect(SliderFill.fraction(of: -1, in: 0 ... 100) == 0)
        #expect(SliderFill.fraction(of: 5, in: 5 ... 5) == 0)
    }

    @Test
    func snappingRoundsToTheStepThenClamps() {
        #expect(DevelopAdjustmentKind.exposure.snapped(0.704) == 0.7)
        #expect(DevelopAdjustmentKind.exposure.snapped(-0.006) == -0.01)
        #expect(DevelopAdjustmentKind.exposure.snapped(9) == 5)
        #expect(DevelopAdjustmentKind.temperature.snapped(5520) == 5500)
        #expect(DevelopAdjustmentKind.temperature.snapped(100) == 2000)
        #expect(DevelopAdjustmentKind.contrast.snapped(12.5) == 13)
    }

    @Test
    func pagesStepAndClampAtTheEnds() {
        #expect(AdjustmentGroup.light.next == .color)
        #expect(AdjustmentGroup.color.previous == .light)
        #expect(AdjustmentGroup.light.previous == .light)
        #expect(AdjustmentGroup.effects.next == .effects)
        #expect(AdjustmentGroup.allCases == [.light, .color, .presence, .detail, .effects])
    }

    @Test
    func aSwipeLeftShowsTheNextPageAndAShortOneNothing() {
        #expect(AdjustmentGroup.color.swiped(by: -40) == .presence)
        #expect(AdjustmentGroup.color.swiped(by: 40)  == .light)
        #expect(AdjustmentGroup.color.swiped(by: -29) == .color)
        #expect(AdjustmentGroup.color.swiped(by: 29)  == .color)
        #expect(AdjustmentGroup.effects.swiped(by: -200) == .effects)
        #expect(AdjustmentGroup.light.swiped(by: 200)    == .light)
    }

    /// fractions is a fill's start, end and thumb for a value, a range and a default, to keep the
    /// tables short. Every case divides whole numbers, so the quotients compare exactly.
    private func fractions(
        _ value       : Double,
        _ range       : ClosedRange<Double>,
        _ defaultValue: Double
    ) -> [Double] {
        let fill = SliderFill(
            value        : value,
            range        : range,
            defaultValue : defaultValue
        )

        return [fill.start, fill.end, fill.thumb]
    }
}
