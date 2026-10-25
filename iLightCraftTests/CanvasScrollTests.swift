//
//  CanvasScrollTests.swift
//  iLightCraftTests
//

import Metal
import simd
import Testing
import UIKit
import UIKit.UIGestureRecognizerSubclass
@testable import iLightCraft

/// CanvasScrollTests drives the canvas's invisible scroll view the way a two-finger trackpad scroll
/// moves it, through its `contentOffset`, and checks what the image does.
@Suite(.serialized, .exclusiveWindow)
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

        try await zoom(canvas, toPercent: 400)

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

        try await zoom(canvas, toPercent: 400)

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

    /// Released with a velocity, the proxy stays where the fingers left it (no system deceleration,
    /// which moved on every other 60 Hz frame in F6's recording) and the image glides on the canvas's
    /// momentum spring by half a second of that velocity. The glide asks for its resting window once,
    /// at full quality, at the release, and for nothing on the way. If UIKit still says it will
    /// decelerate, the glide is the same and the deceleration is stopped where it starts.
    @Test(arguments: [false, true])
    func aReleasedScrollGlidesOnTheCanvasSpringAndAsksForOneWindow(willDecelerate: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy

        try await zoom(canvas, toPercent: 400)

        var requests: [Bool] = []
        canvas.onVisibleWindowChange = { _, isDraft in requests.append(isDraft) }

        let before = canvas.canvasTransform
        let start  = proxy.contentOffset

        // UIScrollView reports points per millisecond: 0.1 is 100 pt/s, a 50 pt glide.
        let target = release(
            canvas,
            proxy          : proxy,
            velocity       : CGPoint(x: 0.1, y: 0),
            willDecelerate : willDecelerate
        )

        if willDecelerate {
            canvas.scrollViewWillBeginDecelerating(proxy)
        }

        #expect(target == start)
        #expect(proxy.contentOffset == start)
        #expect(requests == [false])

        let end = before.offset.x - 50

        try await springEnded(canvas)

        #expect(abs(canvas.canvasTransform.offset.x - end) < 1e-9)

        // Nothing to wait on for a request that must not come: a few more ticks at rest.
        try await Task.sleep(for: .milliseconds(200))

        #expect(canvas.canvasTransform.offset.y == before.offset.y)
        #expect(canvas.canvasTransform.zoom == before.zoom)
        #expect(requests == [false])
    }

    /// At high zoom a release glides exactly as at 400 %: half a second of its velocity, the zoom
    /// kept. The velocity and the edges are in view points at every zoom, so nothing scales with it.
    @Test(arguments: [300.0, 800.0, 3200.0])
    func aReleasedScrollGlidesAtEveryZoom(percent: Double) async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy

        try await zoom(canvas, toPercent: percent)

        let before = canvas.canvasTransform

        _ = release(
            canvas,
            proxy          : proxy,
            velocity       : CGPoint(x: 0.1, y: 0),
            willDecelerate : false
        )

        let end = before.offset.x - 50

        try await springEnded(canvas)

        #expect(abs(canvas.canvasTransform.offset.x - end) < 1e-9)
        #expect(canvas.canvasTransform.zoom == before.zoom)
    }

    /// A trackpad pinch UIKit leaves in `changed` after the fingers moved on to a scroll (F6's edge
    /// session: no end for 15 s) is cancelled when the scroll begins, so the scroll's release still
    /// glides; while it stayed `changed` every release counted as a gesture in progress and stopped.
    @Test
    func aScrollCancelsAStaleTrackpadPinchAndStillGlides() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy
        let pinch  = try #require(
            canvas.gestureRecognizers?.compactMap { $0 as? UIPinchGestureRecognizer }.first
        )

        try await zoom(canvas, toPercent: 400)

        pinch.state = .began
        pinch.state = .changed
        try await Task.sleep(for: .milliseconds(100))

        let before = canvas.canvasTransform

        canvas.scrollViewWillBeginDragging(proxy)

        #expect(pinch.state != .began && pinch.state != .changed)

        _ = release(
            canvas,
            proxy          : proxy,
            velocity       : CGPoint(x: 0.1, y: 0),
            willDecelerate : false
        )

        let end = before.offset.x - 50

        try await springEnded(canvas)

        #expect(abs(canvas.canvasTransform.offset.x - end) < 1e-9)
    }

    /// F6's edge session replayed: from 37.106 s a trackpad pinch sent three bursts of events (9.2 s
    /// and 5.6 s apart) and UIKit never ended it, so it blocked every glide for 15 s. Now each burst
    /// is cancelled `stalePinchTimeout` after its last event, never inside it, the next burst begins
    /// a fresh pinch, and in the gaps a scroll release glides with a full-quality window and a
    /// rubber band springs back, with no scroll beginning to cancel the pinch. Each burst keeps its
    /// recorded timing; the gaps only need to outlast the checks, so the next burst follows 0.5 s later.
    @Test
    func aTrackpadPinchUIKitNeverEndsIsCancelledAfterItsLastEvent() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy
        let pinch  = try #require(
            canvas.gestureRecognizers?.compactMap { $0 as? UIPinchGestureRecognizer }.first
        )
        let log    = PinchLog(pinch)

        try await zoom(canvas, toPercent: 400)

        let bursts = [
            [
                37.106549, 37.144203, 37.156264, 37.177395, 37.194212, 37.210898,
                37.227819, 37.244382, 37.261114, 37.277908, 37.294108,
            ],
            [46.491054, 46.529158, 46.539098, 46.559804],
            [52.172436, 52.212424, 52.213532, 52.222154, 52.243406, 52.259761],
        ]

        var requests: [Bool] = []
        canvas.onVisibleWindowChange = { _, isDraft in requests.append(isDraft) }

        for (index, burst) in bursts.enumerated() {
            let start = ContinuousClock.now + .milliseconds(500)

            for time in burst {
                try await Task.sleep(until: start + .seconds(time - burst[0]), clock: .continuous)

                pinch.state = isPinching(pinch) ? .changed : .began
            }

            try await waitUntil(seconds: 2) { !isPinching(pinch) }

            // One cancel per burst so far: none came between the events of a burst.
            #expect(log.cancels.count == index + 1)

            // The gap: a release with no scroll beginning glides 50 pt, which the stale pinch stopped.
            let before = canvas.canvasTransform

            _ = release(
                canvas,
                proxy          : proxy,
                velocity       : CGPoint(x: 0.1, y: 0),
                willDecelerate : false
            )

            try await springEnded(canvas)

            #expect(abs(canvas.canvasTransform.offset.x - (before.offset.x - 50)) < 1e-9)
            #expect(requests.last == false)

            guard index == 0 else { continue }

            // Pushed far past the right edge without a finger, the image springs back to the edge.
            let resting = proxy.contentOffset

            proxy.contentOffset = CGPoint(x: resting.x - 2000, y: resting.y)

            let pushed = canvas.canvasTransform.offset

            try await springEnded(canvas)

            #expect(canvas.canvasTransform.offset.x < pushed.x - 10)
        }

        #expect(log.cancels.count == 3)

        for cancel in log.cancels {
            let wait = log.entries[cancel].time - log.entries[cancel - 1].time

            #expect(wait >= CanvasView.stalePinchTimeout - 0.005)
            #expect(wait < 1.5)
        }

        for cancel in log.cancels.dropLast() {
            #expect(log.entries[cancel + 1].state == .began)
        }
    }

    /// The longest-spaced pinch that ended in F5 and F6 (F5's second session at 31.464 s: 28
    /// events up to 50 ms apart, then ended) is never cancelled, during it or once it has ended.
    @Test
    func aTrackpadPinchWithEventsUpTo50MillisecondsApartIsNeverCancelled() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let pinch  = try #require(
            canvas.gestureRecognizers?.compactMap { $0 as? UIPinchGestureRecognizer }.first
        )
        let log    = PinchLog(pinch)

        try await zoom(canvas, toPercent: 400)

        let times = [
            31.464079, 31.504701, 31.519873, 31.535184, 31.551878, 31.568739, 31.585136,
            31.601843, 31.618504, 31.635191, 31.651819, 31.668403, 31.685094, 31.701816,
            31.718577, 31.735146, 31.751817, 31.768783, 31.785409, 31.801901, 31.834784,
            31.834870, 31.847338, 31.884895, 31.885007, 31.897343, 31.913994, 31.964078,
        ]
        let start = ContinuousClock.now

        for (index, time) in times.enumerated() {
            try await Task.sleep(until: start + .seconds(time - times[0]), clock: .continuous)

            switch index {
                case 0               : pinch.state = .began
                case times.count - 1 : pinch.state = .ended
                default              : pinch.state = .changed
            }
        }

        // Past every check the events scheduled: none may cancel a pinch that ended.
        try await Task.sleep(for: .seconds(CanvasView.stalePinchTimeout + 0.3))

        #expect(log.entries.first?.state == .began)
        #expect(log.entries.last?.state == .ended)
        #expect(log.cancels.isEmpty)
    }

    /// isPinching(_:) is true while `pinch` is in progress.
    private func isPinching(_ pinch: UIPinchGestureRecognizer) -> Bool {
        pinch.state == .began || pinch.state == .changed
    }

    /// zoom(_:toPercent:) zooms the canvas to `percent` and waits until the zoom spring has landed.
    private func zoom(_ canvas: CanvasView, toPercent percent: Double) async throws {
        canvas.zoom(toPercent: percent)

        try await springEnded(canvas)
        try #require(canvas.canvasTransform.zoom > 2)
    }

    /// springEnded(_:) waits until no spring moves the canvas. The margin is wide on purpose: a
    /// 50 pt glide here rests about 2.2 s after its release, a zoom about 1 s after it starts.
    private func springEnded(_ canvas: CanvasView) async throws {
        try await waitUntil(seconds: 10) { !canvas.isSpringing }
    }

    /// A glide released toward a near edge with far more speed than the room left (F6's recording:
    /// 10,289 pt/s with 409 pt to go) comes to rest on the edge without ever passing it. Before the
    /// velocity cap the spring carried the image up to 658 pt past the edge and back.
    @Test
    func aScrollGlideIntoAnEdgeComesToRestOnItWithoutPassingIt() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy

        try await zoom(canvas, toPercent: 400)

        let before = canvas.canvasTransform.offset

        // 5 pt/ms against the content is 5000 pt/s for the image to the right: 2500 pt projected.
        _ = release(
            canvas,
            proxy          : proxy,
            velocity       : CGPoint(x: -5, y: 0),
            willDecelerate : false
        )

        let samples = try await offsetsUntilRest(of: canvas)
        let edge    = canvas.canvasTransform.offset

        #expect(edge.x > before.x + 100)
        #expect(edge.x < before.x + 2400)
        #expect(samples.allSatisfy { $0.x <= edge.x + 1e-9 })
        #expect(samples.allSatisfy { $0.y == before.y })
    }

    /// A scroll released in the rubber band, still moving outward (F6's recording: 158 pt past the
    /// edge at 11,391 pt/s), settles straight back to the edge. The spring used to carry it a
    /// further 1000 pt out first.
    @Test
    func aScrollReleasedInTheRubberBandSettlesBackWithoutGoingFurther() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }

        let canvas = fixture.canvas
        let proxy  = fixture.proxy

        try await zoom(canvas, toPercent: 400)

        let start = proxy.contentOffset

        // Far past the right edge: the image rubber-bands, then is released still moving right.
        proxy.contentOffset = CGPoint(x: start.x - 2000, y: start.y)
        _ = release(
            canvas,
            proxy          : proxy,
            velocity       : CGPoint(x: -11, y: 0),
            willDecelerate : false
        )

        let released = canvas.canvasTransform.offset
        let samples  = try await offsetsUntilRest(of: canvas)
        let edge     = canvas.canvasTransform.offset

        #expect(edge.x < released.x - 10)
        #expect(samples.allSatisfy { $0.x <= released.x + 1e-9 && $0.x >= edge.x - 1e-9 })
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $1.x <= $0.x + 1e-9 })
    }

    /// release(_:proxy:velocity:willDecelerate:) lifts the fingers off a scroll the way UIKit does,
    /// with `velocity` in the proxy's points per millisecond, and returns the target offset it left.
    private func release(
        _ canvas       : CanvasView,
        proxy          : UIScrollView,
        velocity       : CGPoint,
        willDecelerate : Bool
    ) -> CGPoint {
        var target = CGPoint(x: proxy.contentOffset.x + 500, y: proxy.contentOffset.y)

        canvas.scrollViewWillEndDragging(
            proxy,
            withVelocity        : velocity,
            targetContentOffset : &target
        )
        canvas.scrollViewDidEndDragging(proxy, willDecelerate: willDecelerate)

        return target
    }

    /// offsetsUntilRest(of:) samples the image offset every few milliseconds until no spring moves
    /// it (10 s at most), so a test sees the whole glide, frame by frame.
    private func offsetsUntilRest(of canvas: CanvasView) async throws -> [SIMD2<Double>] {
        let deadline = ContinuousClock.now + .seconds(10)
        var samples  = [canvas.canvasTransform.offset]

        while canvas.isSpringing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(4))

            samples.append(canvas.canvasTransform.offset)
        }

        try #require(!canvas.isSpringing)

        return samples
    }

    /// PinchLog records each state the pinch recognizer reports to its targets, with the time, as
    /// the canvas hears it. A stale pinch shows as `cancelled`.
    @MainActor
    private final class PinchLog: NSObject {

        private(set) var entries: [(state: UIGestureRecognizer.State, time: CFTimeInterval)] = []

        /// cancels are the indices of the `cancelled` entries.
        var cancels: [Int] {
            entries.indices.filter { entries[$0].state == .cancelled }
        }

        init(_ pinch: UIPinchGestureRecognizer) {
            super.init()
            pinch.addTarget(self, action: #selector(record(_:)))
        }

        @objc
        private func record(_ recognizer: UIGestureRecognizer) {
            entries.append((recognizer.state, CACurrentMediaTime()))
        }
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
