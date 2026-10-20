//
//  NativeImagePipelineTests.swift
//  Unveil
//

import XCTest
import CoreImage
import ImageIO
@testable import Unveil

final class NativeImagePipelineTests: XCTestCase {
    func testSonyRAWDoesNotRequireRegisteredType() {
        XCTAssertTrue(NativeImagePipeline.isRAW(fileName: "CJW03953.ARW", typeIdentifier: "public.data"))
        XCTAssertTrue(NativeImagePipeline.isRAW(fileName: "photo.arw"))
        XCTAssertFalse(NativeImagePipeline.isRAW(fileName: "decoded.tiff", typeIdentifier: "public.tiff"))
        XCTAssertFalse(NativeImagePipeline.isRAW(fileName: "photo.jpg"))
    }
    func testFloatingPointWorkingCopyPreservesHighlightsAboveWhite() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return XCTFail("No extended linear color space") }
        let source = folder.appendingPathComponent("hdr-source.tiff"), working = folder.appendingPathComponent("working.tiff")
        let samples = Array(repeating: [Float(3), Float(2), Float(1), Float(1)], count: 64).flatMap { $0 }
        let bytes = samples.withUnsafeBytes { Data($0) }
        let image = CIImage(bitmapData: bytes, bytesPerRow: 8 * 16, size: CGSize(width: 8, height: 8), format: .RGBAf, colorSpace: space)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        try context.writeTIFFRepresentation(of: image, to: source, format: .RGBAf, colorSpace: space, options: [:])
        _ = try NativeImagePipeline.prepare(source: source, destination: working, raw: false)
        guard let reopened = CIImage(contentsOf: working) else { return XCTFail("Could not reopen float TIFF") }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(reopened, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        XCTAssertEqual(pixel[0], 3, accuracy: 0.02)
        XCTAssertEqual(pixel[1], 2, accuracy: 0.02)
    }
    func testHDRHEICRetainsExtendedRange() throws {
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { return XCTFail("No extended color space") }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let samples = Array(repeating: [Float(3), Float(2), Float(1), Float(1)], count: 64).flatMap { $0 }
        let image = CIImage(bitmapData: samples.withUnsafeBytes { Data($0) }, bytesPerRow: 128, size: CGSize(width: 8, height: 8), format: .RGBAf, colorSpace: space)
        let source = folder.appendingPathComponent("hdr.tiff"), output = folder.appendingPathComponent("hdr.heic")
        let context = CIContext()
        try context.writeTIFFRepresentation(of: image, to: source, format: .RGBAf, colorSpace: space, options: [:])
        try NativeImagePipeline.encodeHDR(source: source, destination: output)
        guard let reopened = CIImage(contentsOf: output, options: [.expandToHDR: true]) else { return XCTFail("HDR HEIC missing") }
        var pixel = [Float](repeating: 0, count: 4)
        context.render(reopened, toBitmap: &pixel, rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: space)
        XCTAssertGreaterThan(pixel[0], 1.5, "HDR highlights must survive HEIC encoding")
    }
    func testFullResolutionCameraRAWDecode() throws {
        guard let filename = ProcessInfo.processInfo.environment["UNVEIL_RAW_FIXTURE"] else { throw XCTSkip("Provide a pinned CC0 camera RAW fixture with UNVEIL_RAW_FIXTURE.") }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".tiff")
        defer { try? FileManager.default.removeItem(at: output) }
        let version = try NativeImagePipeline.prepare(source: URL(fileURLWithPath: filename), destination: output, raw: true)
        XCTAssertNotNil(version)
        guard let source = CGImageSourceCreateWithURL(output as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? Int else { return XCTFail("RAW output dimensions unavailable") }
        XCTAssertGreaterThan(width, 2000, "Camera RAW must decode at full resolution, not an embedded thumbnail")
        try NativeImagePipeline.validateFloatTIFF(output)
    }
    func testSDRFileCannotMasqueradeAsFloatHDR() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return XCTFail("No sRGB") }
        try CIContext().writePNGRepresentation(of: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)), to: file, format: .RGBA8, colorSpace: space)
        XCTAssertThrowsError(try NativeImagePipeline.validateFloatTIFF(file))
    }
}
