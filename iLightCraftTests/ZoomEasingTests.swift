//
//  ZoomEasingTests.swift
//  iLightCraftTests
//

import CoreGraphics
import Foundation
import simd
import Testing
@testable import iLightCraft

/// ZoomEasingTests covers the trackpad zoom glide: coarse steps are shown over a few display
/// updates and add up to exactly what the events asked, it goes idle, and the point under the
/// anchor stays put through the steps as with one direct pinch.
struct ZoomEasingTests {

    /// One time constant shows 63 % of a step (in log space), and the rest follows.
    @Test
    func aStepIsShownPartlyAfterOneTimeConstant() {
        var easing = ZoomEasing()
        easing.add(2, around: .zero)

        let shown = easing.step(elapsed: ZoomEasing.timeConstant)

        #expect(abs(log(shown) - log(2) * (1 - exp(-1))) < 1e-9)
        #expect(!easing.isIdle)
    }

    /// At 60 Hz the steps of three coarse events add up to their product and the glide goes idle
    /// within a few tenths of a second; idle steps are 1.
    @Test
    func theGlideAddsUpExactlyAndGoesIdle() {
        var easing = ZoomEasing()
        var total  = 1.0
        var ticks  = 0

        for factor in [1.3, 1.2, 0.9] {
            easing.add(factor, around: .zero)
            total *= easing.step(elapsed: 1.0 / 60)
        }

        while !easing.isIdle, ticks < 60 {
            ticks += 1
            total *= easing.step(elapsed: 1.0 / 60)
        }

        #expect(easing.isIdle)
        #expect(ticks < 30)
        #expect(abs(total - 1.3 * 1.2 * 0.9) < 1e-9)
        #expect(easing.step(elapsed: 1.0 / 60) == 1)
    }

    @Test
    func theAnchorFollowsTheLatestEventAndResetForgets() {
        var easing = ZoomEasing()

        easing.add(1.5, around: CGPoint(x: 10, y: 20))
        easing.add(1.1, around: CGPoint(x: 30, y: 40))
        #expect(easing.anchor == CGPoint(x: 30, y: 40))

        easing.reset()
        #expect(easing.isIdle)

        easing.add(.nan, around: .zero)
        easing.add(0, around: .zero)
        #expect(easing.isIdle)
    }

    /// Applying the glide's steps about the anchor keeps the image point under it fixed, and ends
    /// on the same transform as one direct pinch by the whole factor.
    @Test
    func theStepsKeepThePointUnderTheAnchor() {
        let viewSize = CGSize(width: 800, height: 600)
        let anchor   = CGPoint(x: 600, y: 150)
        let range    = 0.05 ... 32.0
        var eased    = CanvasTransform()
        var direct   = CanvasTransform()
        var easing   = ZoomEasing()

        func imagePoint(_ transform: CanvasTransform) -> SIMD2<Double> {
            let fromCenter = SIMD2<Double>(Double(anchor.x) - 400, Double(anchor.y) - 300)
            return (fromCenter - transform.offset) / transform.zoom
        }

        let before = imagePoint(eased)

        easing.add(2.5, around: anchor)

        while !easing.isIdle {
            eased.pinch(
                by       : easing.step(elapsed: 1.0 / 60),
                around   : easing.anchor,
                range    : range,
                viewSize : viewSize
            )

            #expect(simd_length(imagePoint(eased) - before) < 1e-9)
        }

        direct.pinch(by: 2.5, around: anchor, range: range, viewSize: viewSize)

        #expect(abs(eased.zoom - direct.zoom) < 1e-9)
        #expect(simd_length(eased.offset - direct.offset) < 1e-6)
    }
}
