//
//  NativeImagePipeline.swift
//  Unveil
//

import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Apple camera decoding and HDR encoding at the native import/export boundary.
/// RAW decoding uses Apple's camera support, then hands full-resolution linear float pixels to Rust.
nonisolated enum NativeImagePipeline {
    enum ImageError: Error, LocalizedError {
        case unsupportedRAW, invalidImage, hdrEncodingUnavailable, lostPrecision
        var errorDescription: String? {
            switch self {
            case .unsupportedRAW: return "Apple’s RAW decoder cannot decode this camera file or the required decoder version. No embedded-preview substitution was made."
            case .invalidImage: return "The full-resolution image could not be decoded within the current size limit."
            case .hdrEncodingUnavailable: return "A verified 10-bit HDR HEIC could not be encoded on this device. No SDR substitute was saved."
            case .lostPrecision: return "The image transfer did not retain floating-point precision. The original is unchanged."
            }
        }
    }
    /// Camera extensions remain reliable when a device has no registered vendor UTI.
    static func isRAW(fileName: String, typeIdentifier: String? = nil) -> Bool {
        let suffix = (fileName as NSString).pathExtension.lowercased()
        let cameras: Set<String> = ["arw", "sr2", "srf", "dng", "cr2", "cr3", "crw", "nef", "nrw",
                                    "raf", "orf", "rw2", "rwl", "raw", "pef", "iiq", "mrw", "x3f", "kdc", "mos", "erf"]
        return cameras.contains(suffix)
            || typeIdentifier.flatMap { UTType($0) }?.conforms(to: .rawImage) == true
            || UTType(filenameExtension: suffix)?.conforms(to: .rawImage) == true
    }
    static func prepare(source: URL, destination: URL, raw: Bool, decoderVersion: String? = nil) throws -> String? {
        var usedDecoder: String?
        let image: CIImage
        if raw {
            guard let filter = CIRAWFilter(imageURL: source, options: nil) else { throw ImageError.unsupportedRAW }
            if let decoderVersion {
                let version = CIRAWDecoderVersion(rawValue: decoderVersion)
                guard filter.supportedDecoderVersions.contains(version) else { throw ImageError.unsupportedRAW }
                filter.decoderVersion = version
            }
            usedDecoder = filter.decoderVersion.rawValue
            filter.scaleFactor = 1; filter.isDraftModeEnabled = false
            filter.boostAmount = 0
            if filter.isLocalToneMapSupported { filter.localToneMapAmount = 0 }
            filter.extendedDynamicRangeAmount = 1
            guard let output = filter.outputImage else { throw ImageError.unsupportedRAW }
            image = output
        } else {
            guard let output = CIImage(contentsOf: source, options: [.applyOrientationProperty: true, .expandToHDR: true]) else { throw ImageError.invalidImage }
            image = output
        }
        let extent = image.extent
        guard !extent.isInfinite, !extent.isEmpty, extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0, extent.width * extent.height <= 80_000_000,
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { throw ImageError.invalidImage }
        let available = ProcessAvailableMemory().availableBytes()
        let estimated = extent.width * extent.height * 32
        if available > 0 && estimated > Double(available) * 0.7 {
            throw ImageError.invalidImage
        }
        let context = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: space])
        // Transfer only pixels: inherited CFA/DNG tags can misidentify the decoded TIFF as RAW.
        // Half-float retains values above SDR white; unlike integer TIFF/JPEG it does not clamp HDR.
        do { try context.writeTIFFRepresentation(of: image.settingProperties([:]), to: destination, format: .RGBAh, colorSpace: space, options: [:]) }
        catch { throw raw ? ImageError.unsupportedRAW : ImageError.invalidImage }
        try validateFloatTIFF(destination)
        return usedDecoder
    }
    static func validateFloatTIFF(_ url: URL) throws {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              (properties[kCGImagePropertyIsFloat] as? Bool) == true,
              let depth = properties[kCGImagePropertyDepth] as? Int, depth >= 16 else { throw ImageError.lostPrecision }
    }
    static func encodeHDR(source: URL, destination: URL) throws {
        try validateFloatTIFF(source)
        guard let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]),
              let pq = CGColorSpace(name: CGColorSpace.itur_2100_PQ) else { throw ImageError.invalidImage }
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let cg = context.createCGImage(image, from: image.extent, format: .RGB10, colorSpace: pq),
              let output = CGImageDestinationCreateWithURL(destination as CFURL, UTType.heic.identifier as CFString, 1, nil) else { throw ImageError.hdrEncodingUnavailable }
        var metadata: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 1.0, kCGImagePropertyOrientation: 1]
        if let input = CGImageSourceCreateWithURL(source as CFURL, nil),
           let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any] {
            for key in [kCGImagePropertyExifDictionary, kCGImagePropertyGPSDictionary, kCGImagePropertyIPTCDictionary, kCGImagePropertyTIFFDictionary] {
                metadata[key] = properties[key]
            }
        }
        CGImageDestinationAddImage(output, cg, metadata as CFDictionary)
        guard CGImageDestinationFinalize(output),
              let decoded = CGImageSourceCreateWithURL(destination as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(decoded, 0, nil) as? [CFString: Any],
              let depth = properties[kCGImagePropertyDepth] as? Int, depth >= 10 else { throw ImageError.hdrEncodingUnavailable }
    }
}
