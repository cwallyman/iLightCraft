//
//  PointerInputTests.swift
//  UnveilTests
//

import Metal
import Testing
import UIKit
@testable import Unveil

/// PointerInputTests covers how a mouse or trackpad drives the canvas: the pure mappings (pinch and
/// Cmd + scroll zoom, the momentum a release hands on) and which recognizers hear which devices.
@MainActor
struct PointerInputTests {

    /// A trackpad pinch zooms less than the same finger pinch, in the same direction, and the
    /// recognizer's reset scale makes many steps add up to the one big step.
    @Test
    func aTrackpadPinchIsSlowerThanAFingerPinchAndAddsUpAcrossSteps() {
        func factor(_ scale: Double) -> Double { ZoomScale.indirectPinchFactor(for: scale) }

        #expect(factor(1) == 1)
        #expect(factor(2) > 1 && factor(2) < 2)
        #expect(factor(0.5) < 1 && factor(0.5) > 0.5)
        #expect(abs(factor(2) - pow(2, ZoomScale.indirectPinchExponent)) < 1e-12)
        #expect(ZoomScale.indirectPinchExponent <= 0.5)
        #expect(abs(factor(1.05) * factor(1.05) - factor(1.05 * 1.05)) < 1e-12)
    }

    /// Cmd + scroll: no travel is no zoom, content moving up zooms in, down zooms out by the
    /// inverse (as Photos does), and steps add up.
    @Test
    func cmdScrollZoomIsExponentialInTheTravel() {
        func factor(_ points: Double) -> Double { ZoomScale.scrollZoomFactor(forTranslation: points) }

        #expect(factor(0) == 1)
        #expect(factor(-10) > 1)
        #expect(factor(10) < 1)
        #expect(abs(factor(25) * factor(-25) - 1) < 1e-12)
        #expect(abs(factor(30) * factor(70) - factor(100)) < 1e-12)

        // 100 points of swipe are a gentle 1.5x, not a jump to the next preset.
        #expect(factor(-100) > 1.3 && factor(-100) < 1.7)
    }

    /// A finger's flick glides on at its own velocity; a pointer drag stops where it is let go.
    @Test
    func aPointerReleaseHasNoMomentum() {
        let flick = SIMD2<Double>(2400, -900)

        #expect(CanvasSpring.releaseVelocity(flick, isPointer: false) == flick)
        #expect(CanvasSpring.releaseVelocity(flick, isPointer: true) == .zero)
    }

    /// A trackpad scroll's release glides at half the lift speed, in the same direction.
    @Test
    func aScrollReleaseGlidesDamped() {
        let lift = SIMD2<Double>(1200, -400)

        #expect(CanvasSpring.scrollReleaseVelocity(lift) == lift * CanvasSpring.scrollGlideDamping)
        #expect(CanvasSpring.scrollGlideDamping > 0 && CanvasSpring.scrollGlideDamping < 1)
        #expect(CanvasSpring.scrollReleaseVelocity(.zero) == .zero)
    }

    /// Fingers and the pencil pan one recognizer, the pointer's click-drag another (so only the
    /// finger's gets momentum), and a third hears only scroll events, continuous and wheel.
    @Test
    func eachInputDeviceHasItsOwnPanRecognizer() throws {
        let device  = try #require(MTLCreateSystemDefaultDevice())
        let canvas  = CanvasView(frames: FrameSink(device: device, maxPixels: 16), device: device)
        let pans    = (canvas.gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer }
        let direct  = NSNumber(value: UITouch.TouchType.direct.rawValue)
        let pointer = NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)

        let finger = pans.filter { $0.allowedTouchTypes.contains(direct) }
        let mouse  = pans.filter { $0.allowedTouchTypes.contains(pointer) }
        let scroll = pans.filter { $0.allowedTouchTypes.isEmpty && $0.allowedScrollTypesMask.contains(.continuous) }

        #expect(pans.count == 3)
        #expect(finger.count == 1 && !finger[0].allowedTouchTypes.contains(pointer))
        #expect(mouse.count == 1 && mouse[0].allowedTouchTypes == [pointer])
        #expect(scroll.count == 1 && scroll[0].allowedScrollTypesMask.contains(.discrete))
    }
}
