//
//  EditorSurroundTests.swift
//  iLightCraftTests
//

import Metal
import Testing
import UIKit
@testable import iLightCraft

@MainActor
struct EditorSurroundTests {

    /// The canvas clears to the neutral surround, not black, and sits on it before its first draw.
    @Test
    func theCanvasSitsOnTheNeutralSurround() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let canvas = CanvasView(frames: FrameSink(device: device, maxPixels: 16), device: device)

        #expect(EditorSurround.gray > 0.05 && EditorSurround.gray < 0.2)
        #expect(canvas.backgroundColor == EditorSurround.uiColor)
        let linear = pow((EditorSurround.gray + 0.055) / 1.055, 2.4)
        #expect(EditorSurround.metalClearColor.red == linear)
        #expect(EditorSurround.metalClearColor.green == linear)
        #expect(EditorSurround.metalClearColor.blue == linear)
    }
}
