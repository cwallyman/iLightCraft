//
//  HistogramTests.swift
//  UnveilTests
//

import Foundation
import Metal
import Synchronization
import Testing
@testable import Unveil

/// HistogramTests covers the histogram from the frame sink to the adjust card's state, the clipping
/// rule and its words, the capture summary, and the clipping overlay's state in the session.
@MainActor
struct HistogramTests {

    /// histogram is a 100-pixel histogram with `low` pixels at 0 and `high` at 255 in red.
    private func histogram(
        generation: UInt64,
        low       : Int = 0,
        high      : Int = 0,
        isDraft   : Bool = false
    ) -> FrameHistogram {
        var red = [UInt32](repeating: 0, count: 256)
        red[0]   = UInt32(low)
        red[255] = UInt32(high)
        red[128] = UInt32(100 - low - high)

        let flat = [UInt32](repeating: 0, count: 256)

        return FrameHistogram(
            red         : red,
            green       : flat,
            blue        : flat,
            luma        : flat,
            total       : 100,
            clippedLow  : [low, 0, 0],
            clippedHigh : [high, 0, 0],
            generation  : generation,
            isDraft     : isDraft
        )
    }

    private func deliver(
        _ generation: UInt64,
        to sink     : FrameSink,
        window      : FrameWindow? = nil,
        histogram   : FrameHistogram?
    ) {
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
                window     : window,
                histogram  : histogram
            )
        }
    }

    /// The sink passes on a published preview's histogram, never a window's or a stale frame's.
    @Test
    func theSinkHearsOnlyPublishedPreviewHistograms() throws {
        let sink  = FrameSink(device: try #require(MTLCreateSystemDefaultDevice()), maxPixels: 16)
        let heard = Mutex<[UInt64]>([])
        sink.onHistogram = { histogram in heard.withLock { $0.append(histogram.generation) } }
        let window = FrameWindow(frameWidth: 32, frameHeight: 32, x: 0, y: 0, width: 4, height: 4)

        deliver(2, to: sink, histogram: histogram(generation: 2))
        deliver(3, to: sink, window: window, histogram: histogram(generation: 3))
        deliver(1, to: sink, histogram: histogram(generation: 1))
        deliver(4, to: sink, histogram: histogram(generation: 4))

        #expect(heard.withLock { $0 } == [2, 4])
    }

    @Test
    func anEndIsClippedAboveATenthOfAPercent() {
        let pixels = 100_000
        let below  = FrameHistogram(
            red: [], green: [], blue: [], luma: [], total: pixels,
            clippedLow: [100, 0, 0], clippedHigh: [0, 0, 100], generation: 1, isDraft: false
        )
        let above  = FrameHistogram(
            red: [], green: [], blue: [], luma: [], total: pixels,
            clippedLow: [0, 101, 0], clippedHigh: [0, 0, 2500], generation: 1, isDraft: false
        )

        #expect(!below.isShadowClipped && !below.isHighlightClipped)
        #expect(above.isShadowClipped && above.isHighlightClipped)
        #expect(below.clippingSummary.hasPrefix("Shadows not clipped"))
        #expect(above.clippingSummary.contains("highlights clipped"))
    }

    /// The triangles follow the clipped channels; luminance at the end bin means all three.
    @Test
    func theClippedChannelsTintTheTriangles() {
        var luma = [UInt32](repeating: 0, count: 256)
        luma[255] = 500
        let histogram = FrameHistogram(
            red: [], green: [], blue: [], luma: luma, total: 100_000,
            clippedLow: [0, 50, 2000], clippedHigh: [800, 0, 0], generation: 1, isDraft: false
        )

        #expect(histogram.shadowChannels == [false, false, true])
        #expect(histogram.highlightChannels == [true, true, true])
        #expect(histogram.clippingSummary.hasPrefix("Shadows clipped in blue, "))
        #expect(histogram.clippingSummary.contains("; highlights clipped in all channels, "))
        #expect(FrameHistogram.words(for: "Shadows", channels: [true, false, true], share: 0.01)
            .hasPrefix("Shadows clipped in red and blue"))
    }

    /// The model shows each newer histogram, and drops the previous photo's after an open.
    @Test
    func theModelFollowsTheSinkAndForgetsThePreviousPhoto() async throws {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 64)
        await model.open(pickedURL: URL(filePath: "/tmp/first.RAF"))

        deliver(5, to: engine.frames, histogram: histogram(generation: 5, high: 30))
        try await waitUntil(seconds: 3) { model.histogram?.generation == 5 }
        #expect(model.histogram?.isHighlightClipped == true)

        await model.open(pickedURL: URL(filePath: "/tmp/second.RAF"))
        #expect(model.histogram == nil)

        // A hop from before the open, delivered after it, is the first photo's.
        engine.frames.onHistogram?(histogram(generation: 5))
        deliver(6, to: engine.frames, histogram: histogram(generation: 6))
        try await waitUntil(seconds: 3) { model.histogram?.generation == 6 }
    }

    @Test
    func theCaptureSummaryNamesWhatTheFileRecords() throws {
        let base = #""width":6240,"height":4160,"kind":"raw","format":"RAF""#
        let meta = #""meta":{"iso":200,"shutter":"1/250","aperture":2.799999952316284,"focal_mm":35.0,"camera":"X"}"#
        let full = try JSONDecoder().decode(PhotoInfo.self, from: Data("{\(base),\(meta)}".utf8))
        let none = try JSONDecoder().decode(
            PhotoInfo.self,
            from: Data(#"{\#(base),"meta":{"iso":null,"shutter":"","aperture":null,"focal_mm":null}}"#.utf8)
        )
        let bare = try JSONDecoder().decode(PhotoInfo.self, from: Data("{\(base)}".utf8))

        #expect(full.capture?.summary == "ISO 200 · 1/250 s · f/2.8 · 35 mm")
        #expect(none.capture?.summary == nil)
        #expect(bare.capture == nil)
        #expect(PhotoCapture(iso: nil, shutter: "2", aperture: 8, focalMM: nil).summary == "2 s · f/8")
    }

    /// The overlay outlives page changes and closing the card, and shows only while the card is open.
    @Test
    func theClippingOverlayLivesInTheSession() async {
        let model   = EditorViewModel(engine: FakeEngine(), importer: FakeImporter(), previewPixels: 64)
        let session = EditorSession(viewModel: model, libraryLoader: ControlledPhotoLibraryLoader())
        await model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))

        session.showPanel(.light)
        session.clipping.insert(.highlights)
        session.showPanel(.color)
        #expect(session.clippingOverlay == .highlights)

        session.select(.move)
        #expect(session.clippingOverlay.isEmpty)
        session.select(.adjust)
        #expect(session.clippingOverlay == .highlights)
    }
}
