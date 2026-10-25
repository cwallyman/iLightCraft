//
//  HEICImportTests.swift
//  iLightCraftTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import iLightCraft

/// Exercises generated HEIC images through the same importer and engine used by Files and Photos.
@Suite(.serialized)
struct HEICImportTests {

    @Test(arguments: [1, 6, 8])
    func importEditAndReopenPreservesTheOriginal(orientation: Int) async throws {
        let directory = URL.temporaryDirectory.appending(path: "heic-test-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = try fixture(in: directory, orientation: orientation)
        let bytes    = try Data(contentsOf: original)
        let importer = PhotoImporter(importsDirectory: directory.appending(path: "Imports"))
        let copy     = try importer.importCopy(of: original)
        let manager  = try EngineManager(dataDirectory: TemporaryEngineLibrary.make(), maxPixels: 256)
        let photo    = try await manager.openPhoto(at: copy.url)
        let initial  = try await preview(manager)
        let initialPixel = pixel(in: initial, manager: manager)

        let width  = orientation == 1 ? 96 : 64
        let height = orientation == 1 ? 64 : 96
        #expect(initial.nativeWidth == width)
        #expect(initial.nativeHeight == height)

        try await manager.set(.exposure, to: 0.75)
        let edited = try await preview(manager)
        #expect(edited.generation > initial.generation)
        #expect(pixel(in: edited, manager: manager).reduce(0, +) > initialPixel.reduce(0, +))
        #expect(try await manager.currentValues()[.exposure] == 0.75)

        let reopened = try await manager.openPhoto(at: copy.url)
        #expect(reopened == photo)
        #expect(try await manager.currentValues()[.exposure] == 0.75)
        _ = try await preview(manager)
        #expect(try Data(contentsOf: original) == bytes)
        #expect(try Data(contentsOf: copy.url) == bytes)
        #expect(try importer.importCopy(of: original).isNew == false)
    }

    @Test
    func corruptHEICReportsAnErrorAndAnotherPhotoStillOpens() async throws {
        let directory = URL.temporaryDirectory.appending(path: "heic-bad-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let corrupt = directory.appending(path: "broken.heic")
        try Data([0, 0, 0, 24] + Array("ftypheic".utf8) + [0, 0, 0, 0] + Array("mif1heic".utf8))
            .write(to: corrupt)
        let manager = try EngineManager(dataDirectory: TemporaryEngineLibrary.make(), maxPixels: 256)

        do {
            _ = try await manager.openPhoto(at: corrupt)
            Issue.record("A truncated HEIC must not open")
        } catch {
            #expect(!error.localizedDescription.isEmpty)
        }

        let valid = try fixture(in: directory, orientation: 1)
        _ = try await manager.openPhoto(at: valid)
        _ = try await preview(manager)
    }

    private func preview(_ manager: EngineManager) async throws -> ReadyFrame {
        let generation = try manager.requestPreview(maxPixels: 256, draft: false, before: false)
        try await waitUntil(seconds: 30) { (manager.frames.latest()?.generation ?? 0) >= generation }
        return try #require(manager.frames.latest())
    }

    private func pixel(in frame: ReadyFrame, manager: EngineManager) -> [Int] {
        let offset = (frame.height / 2) * frame.bytesPerRow + (frame.width / 2) * 4
        let bytes  = manager.frames.buffer(at: frame.bufferIndex).contents().assumingMemoryBound(to: UInt8.self)
        return (0..<3).map { Int(bytes[offset + $0]) }
    }

    /// ImageIO encodes our original colored blocks at runtime; no camera or third-party media is bundled.
    private func fixture(in directory: URL, orientation: Int) throws -> URL {
        let space   = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 96 * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [0.25, 0.4, 0.55, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        context.setFillColor(try #require(CGColor(colorSpace: space, components: [0.6, 0.2, 0.1, 1])))
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let image       = try #require(context.makeImage())
        let destination = try #require(CGImageDestinationCreateWithURL(
            directory.appending(path: "fixture.heic") as CFURL, UTType.heic.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, image, [
            kCGImageDestinationLossyCompressionQuality: 0.95,
            kCGImagePropertyOrientation: orientation,
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        let url    = directory.appending(path: "fixture.heic")
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        let stored = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(stored.colorSpace?.name == CGColorSpace.displayP3)
        return url
    }
}
