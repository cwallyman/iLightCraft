//
//  CanvasTextureTests.swift
//  UnveilTests
//

import Metal
import Testing
@testable import Unveil

/// CanvasTextureTests checks the two things the canvas takes on faith at runtime: that the default
/// library carries both canvas shaders, and that a published sink buffer wraps into a zero-copy
/// texture, which is unverified on the simulator.
struct CanvasTextureTests {

    let device: any MTLDevice

    init() throws {
        device = try #require(MTLCreateSystemDefaultDevice())
    }

    @Test
    func theDefaultLibraryHasBothCanvasFunctions() throws {
        let library = try #require(device.makeDefaultLibrary())

        #expect(library.makeFunction(name: CanvasView.vertexFunctionName) != nil)
        #expect(library.makeFunction(name: CanvasView.fragmentFunctionName) != nil)
    }

    @Test
    func theCanvasPipelineBuildsForTheDrawableFormat() throws {
        let pipeline = try CanvasView.makePipelineState(
            device      : device,
            pixelFormat : .bgra8Unorm
        )

        #expect(pipeline.device.registryID == device.registryID)
    }

    @Test
    func aPublishedFrameWrapsIntoATextureOverTheSameMemory() throws {
        let sink   = FrameSink(device: device, maxPixels: 64)
        let width  = 5
        let height = 3

        // Pixel i holds the bytes (i, i + 1, i + 2, 255), so a misplaced row or column shows up.
        var pixels = [UInt8]()
        for index in 0 ..< width * height {
            pixels += [UInt8(index), UInt8(index + 1), UInt8(index + 2), 255]
        }

        pixels.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }

            sink.receive(
                rgba      : base,
                width     : width,
                height    : height,
                stride    : width * 4,
                generation: 1,
                isDraft   : false
            )
        }

        let frame   = try #require(sink.latest())
        let texture = try #require(CanvasView.makeTexture(for: frame, in: sink))
        let buffer  = sink.buffer(at: frame.bufferIndex)

        #expect(texture.pixelFormat == .rgba8Unorm)
        #expect(texture.width == width && texture.height == height)
        #expect(texture.buffer === buffer)

        var readBack = [UInt8](repeating: 0, count: width * height * 4)
        readBack.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }

            texture.getBytes(
                base,
                bytesPerRow : width * 4,
                from        : MTLRegionMake2D(0, 0, width, height),
                mipmapLevel : 0
            )
        }

        #expect(readBack == pixels)
    }
}
