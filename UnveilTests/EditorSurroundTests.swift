//
//  EditorSurroundTests.swift
//  UnveilTests
//

import Metal
import Testing
import UIKit
@testable import Unveil

@MainActor
struct EditorSurroundTests {

    /// The canvas clears to the neutral surround, not black, and sits on it before its first draw.
    @Test
    func theCanvasSitsOnTheNeutralSurround() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let canvas = CanvasView(frames: FrameSink(device: device, maxPixels: 16), device: device)

        #expect(EditorSurround.gray > 0.05 && EditorSurround.gray < 0.2)
        #expect(canvas.backgroundColor == EditorSurround.uiColor)
        #expect(EditorSurround.metalClearColor.red == EditorSurround.gray)
        #expect(EditorSurround.metalClearColor.green == EditorSurround.gray)
        #expect(EditorSurround.metalClearColor.blue == EditorSurround.gray)
    }
}
