//
//  TiledEnhancement.swift
//  Unveil
//

import Foundation
import CoreML
import ImageIO
import UniformTypeIdentifiers

/// TiledEnhancement runs the pinned RGB models in padded tiles and produces an explicit SDR copy.
nonisolated enum TiledEnhancement {
    enum EnhancementError: Error, LocalizedError {
        case unsupportedImage, unsupportedModel, invalidOutput
        var errorDescription: String? {
            switch self {
            case .unsupportedImage: "RGB enhancement supports opaque SDR images whose output fits the 80-megapixel and device memory limits."
            case .unsupportedModel: "The enhancement model does not match the expected image tensor format."
            case .invalidOutput: "The enhancement model returned invalid pixels. No copy was saved."
            }
        }
    }
    static func render(source: URL, destination: URL, mode: EnhancementModel,
                       progress: @escaping @Sendable (Double) -> Void) throws {
        guard let modelURL = mode.installed else { throw DepthModelStore.ModelError.notInstalled }
        guard let decoder = CGImageSourceCreateWithURL(source as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { throw EnhancementError.unsupportedImage }
        let scale = mode == .denoise ? 1 : 2
        guard width > 0, height > 0, width <= 80_000_000 / height / (scale * scale),
              width <= 32768, height <= 32768 else { throw EnhancementError.unsupportedImage }
        let estimate = UInt64(width * height) * UInt64(8 + scale * scale * 4) + 500 * 1024 * 1024
        let available = ProcessAvailableMemory().availableBytes()
        guard available > 0, estimate < available / 5 * 3 else { throw DepthModelStore.ModelError.insufficientMemory }
        guard let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil), image.width == width, image.height == height else {
            throw EnhancementError.unsupportedImage
        }
        let outputWidth = width * scale, outputHeight = height * scale
        var pixels = Data(count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress, let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw EnhancementError.unsupportedImage }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let configuration = MLModelConfiguration(); configuration.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let side = 256, pad = 40, core = 176, modelSide = 1024, plane = modelSide * modelSide
        let pool = 4 / scale
        let tiles = ((width + core - 1) / core) * ((height + core - 1) / core)
        var completed = 0
        var output = Data(count: outputWidth * outputHeight * 4)
        try pixels.withUnsafeBytes { inputBytes in
            guard let source = inputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { throw EnhancementError.unsupportedImage }
            try output.withUnsafeMutableBytes { outputBytes in
                guard let target = outputBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else { throw EnhancementError.invalidOutput }
                for tileY in stride(from: 0, to: height, by: core) {
                    for tileX in stride(from: 0, to: width, by: core) {
                        try Task.checkCancellation()
                        try autoreleasepool {
                            let input = try MLMultiArray(shape: [1, 3, 256, 256], dataType: .float16)
                            guard input.strides.map(\.intValue) == [3 * side * side, side * side, side, 1] else { throw EnhancementError.unsupportedModel }
                            let tensor = input.dataPointer.bindMemory(to: Float16.self, capacity: input.count)
                            for y in 0..<side {
                                let sy = min(height - 1, max(0, tileY + y - pad))
                                for x in 0..<side {
                                    let sx = min(width - 1, max(0, tileX + x - pad))
                                    let pixel = (sy * width + sx) * 4
                                    guard source[pixel + 3] == 255 else { throw EnhancementError.unsupportedImage }
                                    for channel in 0..<3 { tensor[channel * side * side + y * side + x] = Float16(Float(source[pixel + channel]) / 255) }
                                }
                            }
                            let provider = try MLDictionaryFeatureProvider(dictionary: ["input": MLFeatureValue(multiArray: input)])
                            let result = try model.prediction(from: provider)
                            guard let values = result.featureValue(for: "output")?.multiArrayValue,
                                  values.dataType == .float16, values.shape.map(\.intValue) == [1, 3, modelSide, modelSide],
                                  values.strides.map(\.intValue) == [3 * plane, plane, modelSide, 1] else { throw EnhancementError.unsupportedModel }
                            let restored = values.dataPointer.bindMemory(to: Float16.self, capacity: values.count)
                            let copyWidth = min(core, width - tileX) * scale, copyHeight = min(core, height - tileY) * scale
                            for y in 0..<copyHeight {
                                for x in 0..<copyWidth {
                                    let destination = ((tileY * scale + y) * outputWidth + tileX * scale + x) * 4
                                    for channel in 0..<3 {
                                        var sum: Float = 0
                                        for py in 0..<pool { for px in 0..<pool {
                                            let index = channel * plane + (pad * 4 + y * pool + py) * modelSide + pad * 4 + x * pool + px
                                            sum += Float(restored[index])
                                        } }
                                        let value = sum / Float(pool * pool)
                                        guard value.isFinite else { throw EnhancementError.invalidOutput }
                                        target[destination + channel] = UInt8((min(1, max(0, value)) * 255).rounded())
                                    }
                                    target[destination + 3] = 255
                                }
                            }
                        }
                        completed += 1; progress(Double(completed) / Double(tiles))
                    }
                }
            }
        }
        try Task.checkCancellation()
        guard let provider = CGDataProvider(data: output as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let result = CGImage(width: outputWidth, height: outputHeight, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: outputWidth * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let encoder = CGImageDestinationCreateWithURL(destination as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw EnhancementError.invalidOutput }
        CGImageDestinationAddImage(encoder, result, [kCGImagePropertyOrientation: 1] as CFDictionary)
        guard CGImageDestinationFinalize(encoder) else { throw EnhancementError.invalidOutput }
    }
}
