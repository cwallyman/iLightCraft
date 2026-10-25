//
//  FrameFailureTests.swift
//  iLightCraftTests
//

import Metal
import Synchronization
import Testing
@testable import iLightCraft

/// FrameFailureTests covers what a FrameSink does with a failed render and with an invalidation.
struct FrameFailureTests {

    let device: any MTLDevice

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
    }

    private func publish(_ generation: UInt64, to sink: FrameSink, window: FrameWindow? = nil) {
        let pixels = [UInt8](repeating: 9, count: 4 * 4 * 4)

        pixels.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }

            sink.receive(
                rgba       : base,
                width      : 4,
                height     : 4,
                stride     : 16,
                generation : generation,
                isDraft    : false,
                window     : window
            )
        }
    }

    @Test
    func aFailureIsHeardAndTheLastGoodFrameStays() {
        let sink  = FrameSink(device: device, maxPixels: 16)
        let heard = Mutex<[FrameFailure]>([])
        sink.onFailure = { failure in heard.withLock { $0.append(failure) } }

        publish(1, to: sink)
        let failure = FrameFailure(generation: 2, isWindow: false, message: "cannot decode")
        sink.receiveFailure(failure)

        #expect(heard.withLock { $0 } == [failure])
        #expect(sink.latest()?.generation == 1)
    }

    /// A failure older than a published frame says nothing about what is shown: it is not heard.
    @Test
    func aFailureOlderThanAPublishedFrameIsDropped() {
        let sink  = FrameSink(device: device, maxPixels: 16)
        let heard = Mutex<[FrameFailure]>([])
        sink.onFailure = { failure in heard.withLock { $0.append(failure) } }

        publish(5, to: sink)
        sink.receiveFailure(FrameFailure(generation: 4, isWindow: false, message: "late"))
        sink.receiveFailure(FrameFailure(generation: 5, isWindow: false, message: "same"))

        #expect(heard.withLock { $0 }.isEmpty)
    }

    /// A failed window takes the previous window down (it holds older settings than the preview
    /// under it) and wakes the canvas, so the fit preview shows alone; the preview stays.
    @Test
    func aFailedWindowTakesThePreviousWindowDown() {
        let sink   = FrameSink(device: device, maxPixels: 16)
        let woken  = Mutex(0)
        let window = FrameWindow(
            frameWidth  : 400,
            frameHeight : 300,
            x           : 100,
            y           : 50,
            width       : 4,
            height      : 4
        )
        sink.onFrame = { woken.withLock { $0 += 1 } }

        publish(1, to: sink, window: window)
        publish(2, to: sink)
        sink.receiveFailure(FrameFailure(generation: 3, isWindow: true, message: "window failed"))

        #expect(sink.published().window == nil)
        #expect(sink.latest()?.generation == 2)
        #expect(woken.withLock { $0 } == 3)
    }

    @Test
    func invalidateUnpublishesTheFramesAndRefusesOlderOnes() {
        let sink  = FrameSink(device: device, maxPixels: 16)
        let woken = Mutex(0)
        sink.onFrame = { woken.withLock { $0 += 1 } }

        publish(3, to: sink)
        sink.invalidate()

        #expect(sink.latest() == nil)
        #expect(sink.published().window == nil)
        #expect(woken.withLock { $0 } == 2)

        publish(2, to: sink)
        #expect(sink.latest() == nil)

        publish(4, to: sink)
        #expect(sink.latest()?.generation == 4)
    }
}
