//
//  CanvasWindowTests.swift
//  UnveilTests
//

import Metal
import Testing
import UIKit
@testable import Unveil

/// CanvasWindowTests drives a real CanvasView in a window, with frames handed to its sink the way
/// the engine hands them, to check which zoom window it would draw.
///
/// The canvas is 20 x 15 points and the preview 64 x 43 pixels of a 640 x 427 photo, so at fit the
/// preview is enough (0.625 screen pixels per preview pixel at 2x) and at 100 % the canvas wants a
/// window of the photo's own pixels, capped at the sink's 64 pixels.
@Suite(.serialized)
@MainActor
struct CanvasWindowTests {

    /// A full window still rendering when the view zooms back to fit lands after the zoom-out, and
    /// an edit at fit then publishes a newer preview. Zoomed in again to the same frame, the late
    /// window (the old settings) must never be drawn over that preview.
    @Test
    func aWindowLandingAfterTheZoomOutIsNeverDrawnAgain() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        fixture.deliver(generation: 1)
        try await waitUntil(seconds: 3) { fixture.canvas.bounds.width > 0 }

        fixture.canvas.zoom(toPercent: 100)
        let wanted = try await fixture.nextWindow()
        fixture.deliver(generation: 2, window: wanted)
        try await waitUntil(seconds: 3) {
            fixture.sink.published().window.map(fixture.canvas.isShowable) == true
        }

        fixture.canvas.zoomToFit()
        try await waitUntil(seconds: 3) { fixture.lastReport?.window == nil }
        fixture.deliver(generation: 3, window: wanted)
        try await Task.sleep(for: .milliseconds(300))
        fixture.deliver(generation: 4)

        fixture.canvas.zoom(toPercent: 100)
        #expect(try await fixture.nextWindow() == wanted)

        let late = try #require(fixture.sink.published().window)
        #expect(late.generation == 3)
        #expect(!fixture.canvas.isShowable(late))
    }

    /// At 100 % the window quad is moved by less than a pixel onto the drawable's pixel grid, with
    /// its size unchanged, so each pixel samples one texel.
    @Test
    func aOneToOneQuadMovesOntoThePixelGridKeepingItsSize() {
        let drawable = SIMD2<Float>(2360, 1640)
        let half     = drawable / 2
        let start    = SIMD2<Float>(100.3, 200.6) / half - 1
        let size     = SIMD2<Float>(1000, 800) / half
        let quad     = CanvasView.pixelAligned((min: start, max: start + size), drawableSize: drawable)
        let corner   = (quad.min + 1) * half
        let span     = (quad.max - quad.min) * half

        #expect(abs(corner.x - 100) < 0.01 && abs(corner.y - 201) < 0.01)
        #expect(abs(span.x - 1000) < 0.01 && abs(span.y - 800) < 0.01)
    }

    @MainActor
    private final class Fixture {

        let sink  : FrameSink
        let canvas: CanvasView
        let window: UIWindow

        /// lastReport is the newest window the canvas asked for (nil: the preview is enough).
        private(set) var lastReport: (window: FrameWindow?, isDraft: Bool)?

        init() throws {
            let device = try #require(MTLCreateSystemDefaultDevice())
            let scene  = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let root   = UIViewController()

            sink   = FrameSink(device: device, maxPixels: 64)
            canvas = CanvasView(frames: sink, device: device)
            window = UIWindow(windowScene: scene)

            canvas.frame              = CGRect(x: 0, y: 0, width: 20, height: 15)
            window.rootViewController = root
            root.view.addSubview(canvas)
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            canvas.onVisibleWindowChange = { [weak self] window, isDraft in
                self?.lastReport = (window, isDraft)
            }
        }

        /// deliver publishes a 64 x 43 preview, or a window at `window`'s place, as the engine would.
        func deliver(generation: UInt64, window: FrameWindow? = nil) {
            let width  = window?.width ?? 64
            let height = window?.height ?? 43
            let pixels = [UInt8](repeating: UInt8(generation), count: width * height * 4)

            pixels.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }

                sink.receive(
                    rgba         : base,
                    width        : width,
                    height       : height,
                    stride       : width * 4,
                    generation   : generation,
                    isDraft      : false,
                    window       : window,
                    nativeWidth  : 640,
                    nativeHeight : 427
                )
            }
        }

        /// nextWindow waits for the full-quality window the canvas asks for once a zoom rests.
        func nextWindow() async throws -> FrameWindow {
            try await waitUntil(seconds: 5) { lastReport?.window != nil && lastReport?.isDraft == false }

            return try #require(lastReport?.window)
        }
    }
}
