//
//  OnDeviceAnalysis.swift
//  iLightCraft
//

import Foundation
import Vision
import ImageIO
import CoreVideo

/// OnDeviceAnalysis uses Apple's local Vision requests. It never uploads an image.
nonisolated enum OnDeviceAnalysis {
    struct Selection: Sendable {
        let side: Int
        let alpha: [UInt8]
    }
    struct Description: Codable, Sendable {
        let labels: [String]
        let text: [String]
        let faces: Int
        var embedding: [Double]? = nil
    }
    enum AnalysisError: Error, LocalizedError {
        case noSelection, invalidMask, imageUnavailable
        var errorDescription: String? {
            switch self {
            case .noSelection: "No matching selection was found in this image."
            case .invalidMask: "The on-device model returned an unsupported mask."
            case .imageUnavailable: "The analysis preview could not be opened."
            }
        }
    }
    static func selection(at url: URL, people: Bool, background: Bool, point: CGPoint? = nil) throws -> Selection {
        try Task.checkCancellation()
        let handler = VNImageRequestHandler(url: url, options: [:])
        let buffer: CVPixelBuffer
        if people {
            let request = VNGeneratePersonSegmentationRequest()
            request.qualityLevel = .accurate
            request.outputPixelFormat = kCVPixelFormatType_OneComponent8
            try handler.perform([request])
            guard let result = request.results?.first else { throw AnalysisError.noSelection }
            buffer = result.pixelBuffer
        } else {
            let request = VNGenerateForegroundInstanceMaskRequest()
            try handler.perform([request])
            guard let result = request.results?.first, !result.allInstances.isEmpty else { throw AnalysisError.noSelection }
            let instances: IndexSet
            if let point {
                let labels = result.instanceMask
                guard point.x.isFinite, point.y.isFinite,
                      CVPixelBufferGetPixelFormatType(labels) == kCVPixelFormatType_OneComponent8,
                      CVPixelBufferLockBaseAddress(labels, .readOnly) == kCVReturnSuccess else { throw AnalysisError.invalidMask }
                defer { CVPixelBufferUnlockBaseAddress(labels, .readOnly) }
                let width = CVPixelBufferGetWidth(labels), height = CVPixelBufferGetHeight(labels)
                guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(labels) else { throw AnalysisError.invalidMask }
                let x = min(width - 1, Int(min(1, max(0, point.x)) * CGFloat(width)))
                let y = min(height - 1, Int(min(1, max(0, point.y)) * CGFloat(height)))
                let label = Int(base.load(fromByteOffset: y * CVPixelBufferGetBytesPerRow(labels) + x, as: UInt8.self))
                guard label > 0, result.allInstances.contains(label) else { throw AnalysisError.noSelection }
                instances = IndexSet(integer: label)
            } else { instances = result.allInstances }
            buffer = try result.generateScaledMaskForImage(forInstances: instances, from: handler)
        }
        try Task.checkCancellation()
        return try selection(from: buffer, inverted: background)
    }
    /// selection samples the full oriented mask into the engine's bounded normalized grid.
    static func selection(from buffer: CVPixelBuffer, inverted: Bool) throws -> Selection {
        let side = 256
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let format = CVPixelBufferGetPixelFormatType(buffer)
        let stride = format == kCVPixelFormatType_OneComponent8 ? 1 : (format == kCVPixelFormatType_OneComponent16Half ? 2 : 4)
        guard width > 0, height > 0, width <= 16384, height <= 16384,
              rowBytes >= width * stride,
              format == kCVPixelFormatType_OneComponent8 || format == kCVPixelFormatType_OneComponent32Float || format == kCVPixelFormatType_OneComponent16Half,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { throw AnalysisError.invalidMask }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw AnalysisError.invalidMask }
        var alpha = [UInt8](repeating: 0, count: side * side)
        for y in 0..<side {
            let sourceY = min(height - 1, y * height / side)
            for x in 0..<side {
                let sourceX = min(width - 1, x * width / side)
                let offset = sourceY * rowBytes + sourceX * stride
                let value: UInt8
                if stride == 1 { value = base.load(fromByteOffset: offset, as: UInt8.self) }
                else {
                    let sample = stride == 2 ? Float(Float16(bitPattern: base.load(fromByteOffset: offset, as: UInt16.self)))
                        : base.load(fromByteOffset: offset, as: Float.self)
                    guard sample.isFinite else { throw AnalysisError.invalidMask }
                    value = UInt8((min(1, max(0, sample)) * 255).rounded())
                }
                alpha[y * side + x] = inverted ? 255 - value : value
            }
        }
        guard alpha.contains(where: { $0 > 32 }) else { throw AnalysisError.noSelection }
        return Selection(side: side, alpha: alpha)
    }
    static func describe(at url: URL) throws -> Description {
        try Task.checkCancellation()
        let classify = VNClassifyImageRequest()
        let read = VNRecognizeTextRequest()
        read.recognitionLevel = .accurate
        read.usesLanguageCorrection = true
        let faces = VNDetectFaceRectanglesRequest()
        try VNImageRequestHandler(url: url, options: [:]).perform([classify, read, faces])
        try Task.checkCancellation()
        var result = Description(labels: Array((classify.results ?? []).filter { $0.confidence >= 0.15 }.prefix(24).map(\.identifier)),
                           text: Array((read.results ?? []).prefix(80).compactMap { $0.topCandidates(1).first?.string.prefix(256).description }),
                           faces: faces.results?.count ?? 0)
        result.embedding = LocalSemanticSearch.vector(for: (result.labels + result.text).joined(separator: ", "))
        return result
    }
}
