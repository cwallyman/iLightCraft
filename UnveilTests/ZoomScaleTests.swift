//
//  ZoomScaleTests.swift
//  UnveilTests
//

import CoreGraphics
import Testing
@testable import Unveil

struct ZoomScaleTests {

    // A 26 MP photo on an iPad: fit is 44 % of the real pixels.
    private let scale = ZoomScale(percentAtFit: 44)!

    @Test
    func theRangeIs5To3200PercentOfRealPixels() {
        #expect(abs(scale.range.lowerBound * 44 - 5) < 1e-9)
        #expect(abs(scale.range.upperBound * 44 - 3200) < 1e-9)
    }

    @Test
    func fitOutsideThePresetsStaysInsideTheRange() {
        // A huge photo is at 3 % when fitted, a tiny one at 5000 %.
        let hugePhoto = ZoomScale(percentAtFit: 3)!
        let tinyPhoto = ZoomScale(percentAtFit: 5000)!

        #expect(hugePhoto.range.lowerBound == 1)
        #expect(tinyPhoto.range.upperBound == 1)
    }

    @Test
    func zoomInAndOutNeverGoTheWrongWayWhenFitIsOutsideThePresets() {
        let hugePhoto = ZoomScale(percentAtFit: 3)!
        let tinyPhoto = ZoomScale(percentAtFit: 5000)!

        // Fit at 3 %: Zoom Out from fit stays, from 5 % it returns to fit, Zoom In goes to 5 %.
        #expect(hugePhoto.zoomOut(from: 1) == 1)
        #expect(hugePhoto.zoomOut(from: 5.0 / 3) == 1)
        #expect(abs(hugePhoto.percent(forZoom: hugePhoto.zoomIn(from: 1)) - 5) < 1e-9)

        // Fit at 5000 %: Zoom In from fit stays, from 3200 % it returns to fit, Zoom Out goes to 3200 %.
        #expect(tinyPhoto.zoomIn(from: 1) == 1)
        #expect(tinyPhoto.zoomIn(from: 3200.0 / 5000) == 1)
        #expect(abs(tinyPhoto.percent(forZoom: tinyPhoto.zoomOut(from: 1)) - 3200) < 1e-9)
    }

    @Test
    func percentAndZoomConvertBothWays() {
        #expect(scale.percent(forZoom: 1) == 44)
        #expect(abs(scale.zoom(forPercent: 100) - 100 / 44) < 1e-12)
        #expect(scale.zoom(forPercent: 1) == scale.range.lowerBound)
        #expect(scale.zoom(forPercent: 99999) == scale.range.upperBound)
    }

    @Test
    func zoomInAndOutJumpToTheNeighbouringPreset() {
        #expect(abs(scale.percent(forZoom: scale.zoomIn(from: 1)) - 50) < 1e-9)
        #expect(abs(scale.percent(forZoom: scale.zoomOut(from: 1)) - 33.33) < 1e-9)

        // Exactly on a preset, and a hair off it, both move to the next one.
        #expect(abs(scale.percent(forZoom: scale.zoomIn(from: 100 / 44)) - 200) < 1e-9)
        #expect(abs(scale.percent(forZoom: scale.zoomIn(from: 99.99 / 44)) - 200) < 1e-9)
        #expect(abs(scale.percent(forZoom: scale.zoomOut(from: 200 / 44)) - 100) < 1e-9)
        #expect(abs(scale.percent(forZoom: scale.zoomOut(from: 100.01 / 44)) - 66.67) < 1e-9)
    }

    @Test
    func zoomStopsAtTheEndsOfTheRange() {
        #expect(abs(scale.percent(forZoom: scale.zoomIn(from: 3200 / 44)) - 3200) < 1e-9)
        #expect(abs(scale.percent(forZoom: scale.zoomOut(from: 5 / 44)) - 5) < 1e-9)
        #expect(abs(scale.percent(forZoom: scale.zoomOut(from: 6 / 44)) - 5) < 1e-9)
    }

    @Test
    func theStepsAreIncreasingAndSpanTheRange() {
        #expect(ZoomScale.steps == ZoomScale.steps.sorted())
        #expect(ZoomScale.steps.first == ZoomScale.minimumPercent)
        #expect(ZoomScale.steps.last == ZoomScale.maximumPercent)
        #expect(ZoomScale.steps.count == 19)
    }

    @Test
    func fillCoversTheViewAlongTheShortAxis() {
        // A 3:2 photo in a 4:3 view: fit is 0.4 pt/px, covering needs 0.45 pt/px.
        let zoom = scale.fillZoom(
            viewSize  : CGSize(width: 1200, height: 900),
            imageSize : CGSize(width: 3000, height: 2000)
        )

        #expect(abs(zoom - 1.125) < 1e-12)
    }

    @Test
    func ticksFireWhenPassingFitOrRealHundredPercent() {
        func ticks(_ oldZoom: Double, _ newZoom: Double) -> Bool {
            scale.landmarkTick(from: oldZoom, to: newZoom, disarmed: nil).ticks
        }

        #expect(ticks(0.9, 1.1))
        #expect(ticks(1.1, 0.9))
        #expect(ticks(2, 2.4))
        #expect(!ticks(1.1, 2))
        #expect(!ticks(0.2, 0.9))
        #expect(!ticks(1.5, 1.5))
    }

    @Test
    func aLandmarkTicksOnceUntilTheZoomLeavesItsBand() {
        // Crossing fit ticks and disarms it; jitter across fit inside the 2 % band stays silent.
        var tick = scale.landmarkTick(from: 0.95, to: 1.001, disarmed: nil)
        #expect(tick.ticks)
        #expect(tick.disarmed == 1)

        tick = scale.landmarkTick(from: 1.001, to: 0.999, disarmed: tick.disarmed)
        #expect(!tick.ticks)
        tick = scale.landmarkTick(from: 0.999, to: 1.01, disarmed: tick.disarmed)
        #expect(!tick.ticks)

        // Leaving the band re-arms fit, so the next crossing ticks again.
        tick = scale.landmarkTick(from: 1.01, to: 1.05, disarmed: tick.disarmed)
        #expect(!tick.ticks)
        #expect(tick.disarmed == nil)
        tick = scale.landmarkTick(from: 1.05, to: 0.97, disarmed: tick.disarmed)
        #expect(tick.ticks)

        // A disarmed fit does not silence the other landmark, the real 100 %.
        tick = scale.landmarkTick(from: 2.2, to: 2.3, disarmed: 1)
        #expect(tick.ticks)
        #expect(tick.disarmed == 100.0 / 44)
    }

    @Test
    func aTrackpadPinchIsDampedTheSameWayInStepsOrAtOnce() {
        func factor(_ scale: Double) -> Double { ZoomScale.indirectPinchFactor(for: scale) }

        #expect(factor(1) == 1)

        // Damped, but in the same direction as the trackpad.
        #expect(factor(2) > 1 && factor(2) < 2)
        #expect(factor(0.5) < 1 && factor(0.5) > 0.5)

        // The recognizer's scale is reset on every step: many small steps must add up to one big one.
        #expect(abs(factor(1.1) * factor(1.1) * factor(1.1) - factor(1.1 * 1.1 * 1.1)) < 1e-12)
    }

    @Test
    func theLabelIsWholeFrom10PercentAndOneDecimalBelow() {
        #expect(ZoomScale.label(forPercent: 100) == "100")
        #expect(ZoomScale.label(forPercent: 43.6) == "44")
        #expect(ZoomScale.label(forPercent: 10) == "10")
        #expect(ZoomScale.label(forPercent: 9.96) == "10")
        #expect(ZoomScale.label(forPercent: 6.25) == "6.3")
        #expect(ZoomScale.label(forPercent: 5) == "5.0")
        #expect(ZoomScale.label(forPercent: 3200) == "3200")
    }

    @Test
    func anUnknownSizeGivesNoScale() {
        #expect(ZoomScale(percentAtFit: 0) == nil)
        #expect(ZoomScale(percentAtFit: .nan) == nil)
        #expect(
            ZoomScale(
                viewSize    : .zero,
                imageSize   : CGSize(width: 10, height: 10),
                screenScale : 2,
                photoScale  : 1
            ) == nil
        )
    }
}
