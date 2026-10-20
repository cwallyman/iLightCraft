//
//  CanvasTextureTests.swift
//  UnveilTests
//

import Metal
import Testing
@testable import Unveil

/// CanvasTextureTests checks the two things the canvas takes on faith at runtime: that the default
/// library carries both canvas shaders, and that a published sink buffer wraps into a zero-copy
/// texture on device, or a shared texture copy on the simulator.
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
            pixelFormat : .rgba16Float
        )

        #expect(pipeline.device.registryID == device.registryID)
    }

    @Test
    func anHDRFrameRetainsValuesAboveWhiteInItsTexture() throws {
        let sink = FrameSink(device: device, maxPixels: 16)
        let sdr = [UInt8](repeating: 255, count: 4 * 4 * 4)
        let hdr = Array(repeating: [Float16(3).bitPattern, Float16(2).bitPattern,
                                    Float16(1).bitPattern, Float16(1).bitPattern], count: 16).flatMap { $0 }
        sdr.withUnsafeBytes { bytes in
            hdr.withUnsafeBufferPointer { extended in
                guard let base = bytes.baseAddress, let linear = extended.baseAddress else { return }
                sink.receive(rgba: base, width: 4, height: 4, stride: 16,
                             generation: 1, isDraft: false, linearRGBA16: linear)
            }
        }
        let frame = try #require(sink.latest())
        #expect(frame.isHDR)
        let texture = try #require(CanvasView.makeTexture(for: frame, in: sink))
        #expect(texture.pixelFormat == .rgba16Float)
        var values = [UInt16](repeating: 0, count: 64)
        values.withUnsafeMutableBytes { bytes in
            if let base = bytes.baseAddress {
                texture.getBytes(base, bytesPerRow: 32, from: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 0)
            }
        }
        #expect(Float16(bitPattern: values[0]) > 2.9)
    }

    /// The simulator previously aborted here because it rejects shared-buffer texture views.
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
        #if !targetEnvironment(simulator)
        let buffer  = sink.buffer(at: frame.bufferIndex)
        #endif

        #expect(texture.pixelFormat == .rgba8Unorm)
        #expect(texture.width == width && texture.height == height)
        #if targetEnvironment(simulator)
        #expect(texture.buffer == nil)
        #expect(texture.storageMode == .shared)
        #else
        #expect(texture.buffer === buffer)
        #endif

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
