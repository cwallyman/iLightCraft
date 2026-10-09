//
//  CanvasTransformTests.swift
//  UnveilTests
//

import CoreGraphics
import Testing
@testable import Unveil

struct CanvasTransformTests {

    @Test
    func aWideImageFitsTheWidth() {
        let quad = CanvasTransform().quad(
            viewSize  : CGSize(width: 1000, height: 1000),
            imageSize : CGSize(width: 2000, height: 1000)
        )

        #expect(quad.min.x == -1 && quad.max.x == 1)
        #expect(abs(quad.min.y + 0.5) < 1e-6 && abs(quad.max.y - 0.5) < 1e-6)
    }

    @Test
    func pinchIsClampedBetweenAQuarterOfFitAnd16x() {
        var transform = CanvasTransform()

        transform.pinch(by: 100, around: .zero, viewSize: CGSize(width: 100, height: 100))
        #expect(transform.zoom == 16)

        transform.pinch(by: 0.001, around: .zero, viewSize: CGSize(width: 100, height: 100))
        #expect(transform.zoom == 0.25)
    }

    @Test
    func belowFitSettlesBackToFit() {
        var transform = CanvasTransform()
        let view      = CGSize(width: 1000, height: 1000)

        transform.pinch(by: 0.5, around: CGPoint(x: 100, y: 100), viewSize: view)

        #expect(transform.settled(viewSize: view, imageSize: view) == CanvasTransform())
    }

    @Test
    func settlingPushesTheImageBackInsideItsEdges() {
        // A square image at 2x in a square view overflows by 500 points per side.
        let view      = CGSize(width: 1000, height: 1000)
        let transform = CanvasTransform(zoom: 2, offset: SIMD2(800, -30))

        let settled = transform.settled(viewSize: view, imageSize: view)

        #expect(settled.zoom == 2)
        #expect(settled.offset == SIMD2(500, -30))
    }

    @Test
    func panningPastAnEdgeMovesLessThanTheFinger() {
        let view      = CGSize(width: 1000, height: 1000)
        var inside    = CanvasTransform(zoom: 2)
        var pastEdge  = CanvasTransform(zoom: 2, offset: SIMD2(500, 0))

        inside.pan(by: CGPoint(x: 100, y: 0), viewSize: view, imageSize: view)
        pastEdge.pan(by: CGPoint(x: 100, y: 0), viewSize: view, imageSize: view)

        #expect(inside.offset.x == 100)
        #expect(pastEdge.offset.x > 500 && pastEdge.offset.x - 500 <= 50)

        pastEdge.pan(by: CGPoint(x: -100, y: 0), viewSize: view, imageSize: view)
        #expect(pastEdge.offset.x < 500)
    }

    @Test
    func doubleTapTogglesFitAndActualPixelsAroundTheTap() {
        // A 4000 px image in a 1000 pt view at 2x: fit is 0.25 pt per pixel, so 100 % is zoom 2.
        let view   = CGSize(width: 1000, height: 1000)
        let image  = CGSize(width: 4000, height: 4000)
        let finger = CGPoint(x: 600, y: 500)
        let before = CanvasTransform().imagePoint(at: finger, viewSize: view, imageSize: image)

        let zoomed = CanvasTransform().toggledZoom(at: finger, viewSize: view, imageSize: image, screenScale: 2)
        let after  = zoomed.imagePoint(at: finger, viewSize: view, imageSize: image)

        #expect(zoomed.zoom == 2)
        #expect(zoomed.screenPixelsPerImagePixel(viewSize: view, imageSize: image, screenScale: 2) == 1)
        #expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5)
        #expect(zoomed.toggledZoom(at: finger, viewSize: view, imageSize: image, screenScale: 2) == CanvasTransform())
    }

    @Test
    func doubleTapZoomsAtLeastToTwiceFit() {
        // The preview is about screen-sized, so 100 % is fit: the tap still zooms in.
        let view  = CGSize(width: 1000, height: 1000)
        let image = CGSize(width: 2000, height: 2000)

        let zoomed = CanvasTransform().toggledZoom(at: .zero, viewSize: view, imageSize: image, screenScale: 2)

        #expect(zoomed.zoom == CanvasTransform.minimumToggleZoom)
    }

    @Test
    func pinchKeepsThePointUnderTheFingers() {
        var transform = CanvasTransform()
        let view      = CGSize(width: 1000, height: 1000)
        let image     = CGSize(width: 1000, height: 1000)
        let finger    = CGPoint(x: 750, y: 500)
        let before    = transform.imagePoint(at: finger, viewSize: view, imageSize: image)

        transform.pinch(by: 2, around: finger, viewSize: view)

        let after = transform.imagePoint(at: finger, viewSize: view, imageSize: image)
        #expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5)
    }

    @Test
    func resetReturnsToFit() {
        var transform = CanvasTransform()

        transform.pinch(by: 3, around: .zero, viewSize: CGSize(width: 100, height: 100))
        transform.pan(by: CGPoint(x: 40, y: 10), viewSize: .zero, imageSize: .zero)
        transform.reset()

        #expect(transform == CanvasTransform())
    }
}
