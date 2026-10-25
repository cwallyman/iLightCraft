//
//  CanvasTransformTests.swift
//  iLightCraftTests
//

import CoreGraphics
import Testing
@testable import iLightCraft

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
    func pinchStretchesPastTheRangeByAtMostAQuarter() {
        var transform = CanvasTransform()
        let view      = CGSize(width: 100, height: 100)

        // Inside the range the zoom follows the fingers exactly.
        transform.pinch(by: 8, around: .zero, range: 0.1 ... 16, viewSize: view)
        #expect(abs(transform.zoom - 8) < 1e-12)

        // Past an end it moves less than the fingers, and stops at 1.25 times the end.
        transform.pinch(by: 2.5, around: .zero, range: 0.1 ... 16, viewSize: view)
        #expect(transform.zoom > 16 && transform.zoom < 20)

        transform.pinch(by: 100, around: .zero, range: 0.1 ... 16, viewSize: view)
        #expect(abs(transform.zoom - 20) < 1e-9)

        transform.pinch(by: 0.000001, around: .zero, range: 0.1 ... 16, viewSize: view)
        #expect(abs(transform.zoom - 0.08) < 1e-9)
    }

    @Test
    func aStretchedZoomSettlesBackToTheLimitAroundTheFingers() {
        var transform = CanvasTransform()
        let view      = CGSize(width: 1000, height: 1000)
        let image     = CGSize(width: 2000, height: 2000)
        let finger    = CGPoint(x: 700, y: 400)

        transform.pinch(by: 40, around: finger, range: 0.05 ... 32, viewSize: view)
        #expect(transform.zoom > 32)

        let before  = transform.imagePoint(at: finger, viewSize: view, imageSize: image)
        let settled = transform.settled(
            viewSize  : view,
            imageSize : image,
            range     : 0.05 ... 32,
            around    : finger
        )
        let after   = settled.imagePoint(at: finger, viewSize: view, imageSize: image)

        #expect(abs(settled.zoom - 32) < 1e-9)
        #expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5)

        // Below the range it returns to the lower end, centred since the image is smaller than the view.
        transform.pinch(by: 0.0001, around: finger, range: 0.05 ... 32, viewSize: view)
        let low = transform.settled(
            viewSize  : view,
            imageSize : image,
            range     : 0.05 ... 32,
            around    : finger
        )

        #expect(abs(low.zoom - 0.05) < 1e-9)
        #expect(low.offset == .zero)
    }

    @Test
    func belowFitStaysAndIsCentered() {
        var transform = CanvasTransform()
        let view      = CGSize(width: 1000, height: 1000)

        transform.pinch(by: 0.5, around: CGPoint(x: 100, y: 100), range: 0.05 ... 32, viewSize: view)
        let settled = transform.settled(viewSize: view, imageSize: view)

        #expect(settled.zoom == 0.5)
        #expect(settled.offset == .zero)
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

        let zoomed = CanvasTransform().toggledZoom(
            at         : finger,
            viewSize   : view,
            imageSize  : image,
            screenScale: 2,
            photoScale : 1
        )
        let after  = zoomed.imagePoint(at: finger, viewSize: view, imageSize: image)

        #expect(zoomed.zoom == 2)
        let scale = ZoomScale(
            viewSize    : view,
            imageSize   : image,
            screenScale : 2,
            photoScale  : 1
        )
        #expect(scale?.percent(forZoom: zoomed.zoom) == 100)
        #expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5)
        let back = zoomed.toggledZoom(
            at         : finger,
            viewSize   : view,
            imageSize  : image,
            screenScale: 2,
            photoScale : 1
        )
        #expect(back == CanvasTransform())
    }

    @Test
    func doubleTapZoomsAtLeastToTwiceFit() {
        // The preview is about screen-sized, so 100 % is fit: the tap still zooms in.
        let view  = CGSize(width: 1000, height: 1000)
        let image = CGSize(width: 2000, height: 2000)

        let zoomed = CanvasTransform().toggledZoom(
            at         : .zero,
            viewSize   : view,
            imageSize  : image,
            screenScale: 2,
            photoScale : 1
        )

        #expect(zoomed.zoom == CanvasTransform.minimumToggleZoom)
    }

    @Test
    func pinchKeepsThePointUnderTheFingers() {
        var transform = CanvasTransform()
        let view      = CGSize(width: 1000, height: 1000)
        let image     = CGSize(width: 1000, height: 1000)
        let finger    = CGPoint(x: 750, y: 500)
        let before    = transform.imagePoint(at: finger, viewSize: view, imageSize: image)

        transform.pinch(by: 2, around: finger, range: 0.05 ... 32, viewSize: view)

        let after = transform.imagePoint(at: finger, viewSize: view, imageSize: image)
        #expect(abs(before.x - after.x) < 0.5 && abs(before.y - after.y) < 0.5)
    }

    @Test
    func resetReturnsToFit() {
        var transform = CanvasTransform()

        transform.pinch(by: 3, around: .zero, range: 0.05 ... 32, viewSize: CGSize(width: 100, height: 100))
        transform.pan(by: CGPoint(x: 40, y: 10), viewSize: .zero, imageSize: .zero)
        transform.reset()

        #expect(transform == CanvasTransform())
    }

    @Test
    func doubleTapZoomsToThePhotosReal100Percent() {
        // A 2000 px preview of a 6000 px photo: real 100 % is 3 screen pixels per preview pixel.
        let view  = CGSize(width: 1000, height: 1000)
        let image = CGSize(width: 2000, height: 2000)
        let scale = CanvasTransform.photoScale(previewSize: image, photoSize: CGSize(width: 6000, height: 6000))

        let zoomed = CanvasTransform().toggledZoom(
            at         : .zero,
            viewSize   : view,
            imageSize  : image,
            screenScale: 2,
            photoScale : scale
        )
        let shown  = ZoomScale(
            viewSize    : view,
            imageSize   : image,
            screenScale : 2,
            photoScale  : scale
        )?.percent(forZoom: zoomed.zoom) ?? 0

        #expect(abs(zoomed.zoom - 3) < 1e-9)
        #expect(abs(shown - 100) < 1e-9)
    }

    @Test
    func theZoomPercentageIsMeasuredAgainstThePhotosRealPixels() {
        let preview = CGSize(width: 2752, height: 1835)
        let photo   = CGSize(width: 6240, height: 4160)
        let scale   = CanvasTransform.photoScale(previewSize: preview, photoSize: photo)

        // One screen pixel per preview pixel at fit is 44% of a 26 MP photo.
        #expect(Int((scale * 100).rounded()) == 44)

        // The real 100% needs this many screen pixels per preview pixel.
        #expect(abs(1 / scale - 6240.0 / 2752) < 1e-9)

        // A portrait photo is measured on its long edge too, and an unknown size changes nothing.
        let portrait = CGSize(width: 4160, height: 6240)
        #expect(CanvasTransform.photoScale(previewSize: preview, photoSize: portrait) == scale)
        #expect(CanvasTransform.photoScale(previewSize: preview, photoSize: .zero) == 1)
    }
}
