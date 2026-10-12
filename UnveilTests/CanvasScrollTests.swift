//
//  CanvasScrollTests.swift
//  UnveilTests
//

import Metal
import simd
import Testing
import UIKit
@testable import Unveil

/// CanvasScrollTests drives the canvas's invisible scroll view the way a two-finger trackpad scroll
/// moves it, through its `contentOffset`, and checks what the image does.
@Suite(.serialized)
@MainActor
struct CanvasScrollTests {

    /// Zoomed in, the proxy's travel pans the image the other way, one to one (content follows the
    /// fingers), and recentring the proxy at the end of the glide leaves the image where it is.
    @Test
    func theScrollViewsTravelPansTheImageOneToOne() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy

        canvas.zoom(toPercent: 400)
        try await waitUntil(seconds: 3) { canvas.canvasTransform.zoom > 5 }
        try await Task.sleep(for: .seconds(1))

        let before = canvas.canvasTransform
        let start  = proxy.contentOffset

        proxy.contentOffset = CGPoint(x: start.x + 5, y: start.y + 7)

        #expect(canvas.canvasTransform.zoom == before.zoom)
        #expect(abs(canvas.canvasTransform.offset.x - (before.offset.x - 5)) < 1e-9)
        #expect(abs(canvas.canvasTransform.offset.y - (before.offset.y - 7)) < 1e-9)

        let moved = canvas.canvasTransform

        canvas.scrollViewDidEndDecelerating(proxy)

        #expect(proxy.contentOffset == start)
        #expect(canvas.canvasTransform == moved)
    }

    /// The proxy moving on its own (a wheel notch's animation, as a programmatic offset change is
    /// seen) past an edge stops there and springs back, as a glide does: at fit nothing can pan, so
    /// the rubber-banded image returns to the centre without any end-of-scroll callback.
    @Test
    func aGlidePastAnEdgeStopsAndSpringsBack() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy
        let start  = proxy.contentOffset

        proxy.contentOffset = CGPoint(x: start.x, y: start.y + 60)

        #expect(canvas.canvasTransform.offset.y < 0)

        try await waitUntil(seconds: 3) { canvas.canvasTransform.offset == .zero }
    }

    /// A two-finger scroll still gliding when a trackpad zoom starts: the zoom stops the glide, and
    /// the image point under the pointer stays under it through the whole eased zoom. In F5's
    /// recordings stopping a glide made the proxy report an offset 200 to 700 pt past its last step,
    /// inside the stop, and the image jumped by that much; the proxy here reports the same way.
    @Test
    func aTrackpadZoomDuringAScrollGlideKeepsThePointUnderThePointer() async throws {
        let stopping = StopReportingScrollView()
        let fixture  = try Fixture(scrollProxy: stopping)
        defer { fixture.window.isHidden = true }

        let canvas  = fixture.canvas
        let proxy   = fixture.proxy
        let pointer = CGPoint(x: 150, y: 40)

        func imagePoint(_ transform: CanvasTransform) -> SIMD2<Double> {
            let fromCenter = SIMD2<Double>(Double(pointer.x) - 100, Double(pointer.y) - 75)
            return (fromCenter - transform.offset) / transform.zoom
        }

        canvas.zoom(toPercent: 400)
        try await waitUntil(seconds: 3) { canvas.canvasTransform.zoom > 5 }
        try await Task.sleep(for: .seconds(1))

        let start = proxy.contentOffset

        // A small glide step the canvas follows; the stop will then report a jump of 600 pt.
        let jump = CGPoint(x: start.x + 610, y: start.y + 13)

        proxy.contentOffset   = CGPoint(x: start.x + 10, y: start.y + 5)
        stopping.reportAtStop = jump

        let before = canvas.canvasTransform
        let zoom   = before.zoom * 1.5

        canvas.easeZoom(by: 1.5, around: pointer)

        // The stop did report the jump, and the image did not follow it.
        #expect(stopping.reportAtStop == nil)
        #expect(proxy.contentOffset == jump)
        #expect(canvas.canvasTransform.offset == before.offset)

        try await waitUntil(seconds: 2) { abs(canvas.canvasTransform.zoom - zoom) < 1e-9 }
        try await Task.sleep(for: .milliseconds(100))

        let after = canvas.canvasTransform

        #expect(abs(after.zoom - zoom) < 1e-9)
        #expect(simd_length(imagePoint(after) - imagePoint(before)) < 1e-6)
    }

    /// StopReportingScrollView stops a glide the way the iPad did: asked to stay where it is, it
    /// first moves to `reportAtStop`, so its delegate hears that offset inside the stop.
    private final class StopReportingScrollView: UIScrollView {

        var reportAtStop: CGPoint?

        override func setContentOffset(_ contentOffset: CGPoint, animated: Bool) {
            guard !animated, let jump = reportAtStop else {
                super.setContentOffset(contentOffset, animated: animated)
                return
            }

            reportAtStop = nil
            super.setContentOffset(jump, animated: false)
        }
    }

    @MainActor
    private final class Fixture {

        let canvas: CanvasView
        let window: UIWindow
        let proxy : UIScrollView

        /// init publishes a 64 x 43 preview of a 640 x 427 photo to a 200 x 150 pt canvas in a window.
        init(scrollProxy: UIScrollView = UIScrollView()) throws {
            let device = try #require(MTLCreateSystemDefaultDevice())
            let scene  = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let sink   = FrameSink(device: device, maxPixels: 64)
            let root   = UIViewController()
            let pixels = [UInt8](repeating: 128, count: 64 * 43 * 4)

            pixels.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }

                sink.receive(
                    rgba         : base,
                    width        : 64,
                    height       : 43,
                    stride       : 64 * 4,
                    generation   : 1,
                    isDraft      : false,
                    nativeWidth  : 640,
                    nativeHeight : 427
                )
            }

            canvas = CanvasView(frames: sink, device: device, scrollProxy: scrollProxy)
            window = UIWindow(windowScene: scene)

            canvas.frame              = CGRect(x: 0, y: 0, width: 200, height: 150)
            window.rootViewController = root
            root.view.addSubview(canvas)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            proxy = try #require(canvas.subviews.compactMap { $0 as? UIScrollView }.first)
        }
    }
}
