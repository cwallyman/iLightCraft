//
//  DepthLensBlur.swift
//  iLightCraft
//

import Foundation
import CoreImage
import CoreML
import Vision

/// DepthLensBlur estimates relative depth locally and creates a full-resolution float TIFF copy.
nonisolated enum DepthLensBlur {
    static func render(source: URL, destination: URL, amount: Double, focus: Double, range: Double) throws {
        guard let modelURL = DepthModelStore.installed else { throw DepthModelStore.ModelError.notInstalled }
        guard amount.isFinite, focus.isFinite, range.isFinite,
              (0...100).contains(amount), (0...1).contains(focus), (0...1).contains(range),
              let image = CIImage(contentsOf: source, options: [.applyOrientationProperty: true]),
              !image.extent.isEmpty, !image.extent.isInfinite,
              image.extent.width * image.extent.height <= 80_000_000,
              let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB) else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
        let available = ProcessAvailableMemory().availableBytes()
        let estimate = image.extent.width * image.extent.height * 48 + 500 * 1024 * 1024
        guard available > 0 && estimate < Double(available) * 0.6 else { throw DepthModelStore.ModelError.insufficientMemory }
        try Task.checkCancellation()
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        let request = try VNCoreMLRequest(model: VNCoreMLModel(for: model))
        request.imageCropAndScaleOption = .scaleFill
        let edge: CGFloat = 1024
        let scale = min(1, edge / max(image.extent.width, image.extent.height))
        let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let cg = context.createCGImage(small, from: small.extent, format: .RGBA8, colorSpace: sRGB) else {
            throw OnDeviceAnalysis.AnalysisError.imageUnavailable
        }
        try VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
        let depth: CIImage
        if let buffer = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer {
            depth = CIImage(cvPixelBuffer: buffer)
        } else if let result = request.results?.first as? VNCoreMLFeatureValueObservation,
                  let array = result.featureValue.multiArrayValue {
            depth = try depthImage(array)
        } else { throw OnDeviceAnalysis.AnalysisError.invalidMask }
        try Task.checkCancellation()
        // The relative-depth model is not a metric distance sensor. Focus/range are normalized.
        var minimum = [Float](repeating: 0, count: 4)
        var maximum = [Float](repeating: 0, count: 4)
        let extent = CIVector(cgRect: depth.extent)
        context.render(depth.applyingFilter("CIAreaMinimum", parameters: [kCIInputExtentKey: extent]), toBitmap: &minimum,
                       rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        context.render(depth.applyingFilter("CIAreaMaximum", parameters: [kCIInputExtentKey: extent]), toBitmap: &maximum,
                       rowBytes: 16, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf, colorSpace: nil)
        guard let lo = minimum.first, let hi = maximum.first, lo.isFinite, hi.isFinite, hi > lo else {
            throw OnDeviceAnalysis.AnalysisError.invalidMask
        }
        let gain = 1 / Double(hi - lo)
        let normalized = depth.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
            "inputBiasVector": CIVector(x: -Double(lo) * gain, y: -Double(lo) * gain, z: -Double(lo) * gain, w: 0)])
        let focusImage = CIImage(color: CIColor(red: focus, green: focus, blue: focus)).cropped(to: depth.extent)
        let distance = normalized.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: focusImage])
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1 / max(0.05, 1 - range), y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1 / max(0.05, 1 - range), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1 / max(0.05, 1 - range), w: 0),
                "inputBiasVector": CIVector(x: -range / max(0.05, 1 - range), y: -range / max(0.05, 1 - range), z: -range / max(0.05, 1 - range), w: 0)])
            .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
            .transformed(by: CGAffineTransform(scaleX: image.extent.width / depth.extent.width, y: image.extent.height / depth.extent.height))
        let radius = max(image.extent.width, image.extent.height) * amount / 100 * 0.02
        let result = image.clampedToExtent().applyingFilter("CIMaskedVariableBlur", parameters: ["inputMask": distance, kCIInputRadiusKey: radius]).cropped(to: image.extent)
        try context.writeTIFFRepresentation(of: result.settingProperties([:]), to: destination, format: .RGBAh, colorSpace: space, options: [:])
        try NativeImagePipeline.validateFloatTIFF(destination)
    }
    private static func depthImage(_ array: MLMultiArray) throws -> CIImage {
        let dimensions = array.shape.map(\.intValue)
        guard let width = dimensions.last, dimensions.count >= 2 else { throw OnDeviceAnalysis.AnalysisError.invalidMask }
        let height = dimensions[dimensions.count - 2]
        guard width > 0, height > 0, width <= 2048, height <= 2048, array.count == width * height else {
            throw OnDeviceAnalysis.AnalysisError.invalidMask
        }
        var values = [Float](repeating: 0, count: array.count)
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for index in values.indices {
            let value = array[index].floatValue
            guard value.isFinite else { throw OnDeviceAnalysis.AnalysisError.invalidMask }
            values[index] = value; lo = min(lo, value); hi = max(hi, value)
        }
        let span = max(hi - lo, 0.00001)
        for index in values.indices { values[index] = (values[index] - lo) / span }
        let bytes = values.withUnsafeBytes { Data($0) }
        return CIImage(bitmapData: bytes, bytesPerRow: width * 4, size: CGSize(width: width, height: height), format: .Lf, colorSpace: CGColorSpaceCreateDeviceGray())
    }
}
