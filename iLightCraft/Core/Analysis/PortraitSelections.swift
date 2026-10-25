import Foundation
import Vision
import CoreML
import CoreImage
import CoreVideo

/// Model inference stays on device; every saved person has independent normalized coverage.
nonisolated enum PortraitSelections {
    struct NamedSelection: Sendable {
        let name: String
        let selection: OnDeviceAnalysis.Selection
    }

    static func people(at url: URL, skin: Bool) throws -> [NamedSelection] {
        try Task.checkCancellation()
        let handler = VNImageRequestHandler(url: url, options: [:])
        let request = VNGeneratePersonInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw OnDeviceAnalysis.AnalysisError.noSelection
        }
        guard observation.allInstances.count <= 20 else { throw SelectionError.tooManyPeople }
        var people: [OnDeviceAnalysis.Selection] = []
        for instance in observation.allInstances {
            try Task.checkCancellation()
            let buffer = try observation.generateScaledMaskForImage(forInstances: IndexSet(integer: instance), from: handler)
            people.append(try OnDeviceAnalysis.selection(from: buffer, inverted: false))
        }
        // Stable, visual numbering from left to right instead of opaque Vision instance IDs.
        people.sort { center($0) < center($1) }
        var results: [NamedSelection] = []
        for (index, person) in people.enumerated() {
            try Task.checkCancellation()
            let selection = skin ? try skinSelection(at: url, person: person) : person
            if selection.alpha.contains(where: { $0 > 32 }) {
                results.append(NamedSelection(name: "Person \(index + 1)\(skin ? " — Skin" : "")", selection: selection))
            }
        }
        guard !results.isEmpty else { throw OnDeviceAnalysis.AnalysisError.noSelection }
        return results
    }

    private static func center(_ mask: OnDeviceAnalysis.Selection) -> Double {
        var weight = 0.0, sum = 0.0
        for (index, alpha) in mask.alpha.enumerated() {
            weight += Double(alpha); sum += Double(index % mask.side) * Double(alpha)
        }
        return weight > 0 ? sum / weight : 0
    }

    static func sky(at url: URL) throws -> OnDeviceAnalysis.Selection {
        let model = try loadModel("SkySegSmall")
        let request = try VNCoreMLRequest(model: VNCoreMLModel(for: model))
        request.imageCropAndScaleOption = .scaleFill
        try VNImageRequestHandler(url: url, options: [:]).perform([request])
        try Task.checkCancellation()
        guard let buffer = (request.results?.first as? VNPixelBufferObservation)?.pixelBuffer else {
            throw OnDeviceAnalysis.AnalysisError.invalidMask
        }
        return try OnDeviceAnalysis.selection(from: buffer, inverted: false)
    }

    private static func loadModel(_ name: String) throws -> MLModel {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mlmodelc") else { throw SelectionError.modelMissing }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        return try MLModel(contentsOf: url, configuration: configuration)
    }

    private static func skinSelection(at url: URL, person: OnDeviceAnalysis.Selection) throws -> OnDeviceAnalysis.Selection {
        // Crop each person's silhouette with a little context, then map skin probabilities back
        // into the original image and intersect them with that person's mask.
        guard let source = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
              source.extent.width > 0, source.extent.height > 0 else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
        let side = person.side
        var left = side, top = side, right = 0, bottom = 0
        for (index, value) in person.alpha.enumerated() where value > 32 {
            left = min(left, index % side); right = max(right, index % side)
            top = min(top, index / side); bottom = max(bottom, index / side)
        }
        guard left <= right, top <= bottom else { throw OnDeviceAnalysis.AnalysisError.noSelection }
        let padding = 8
        left = max(0, left - padding); top = max(0, top - padding)
        right = min(side - 1, right + padding); bottom = min(side - 1, bottom + padding)
        let w = right - left + 1, h = bottom - top + 1
        let bounds = CGRect(x: source.extent.minX + CGFloat(left) / CGFloat(side) * source.extent.width,
                            y: source.extent.minY + CGFloat(side - bottom - 1) / CGFloat(side) * source.extent.height,
                            width: CGFloat(w) / CGFloat(side) * source.extent.width,
                            height: CGFloat(h) / CGFloat(side) * source.extent.height)
        let crop = source.cropped(to: bounds).transformed(by: CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY))
            .transformed(by: CGAffineTransform(scaleX: 256 / bounds.width, y: 256 / bounds.height))
        let context = CIContext(options: [.cacheIntermediates: false])
        var pixels = [UInt8](repeating: 0, count: 256 * 256 * 4)
        context.render(crop, toBitmap: &pixels, rowBytes: 256 * 4, bounds: CGRect(x: 0, y: 0, width: 256, height: 256),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        let model = try loadModel("SkinSeg")
        let input = try MLMultiArray(shape: [1, 256, 256, 3], dataType: .float32)
        for y in 0..<256 {
            for x in 0..<256 {
                for c in 0..<3 {
                    input[(y * 256 + x) * 3 + c] = NSNumber(value: Float(pixels[(y * 256 + x) * 4 + c]) / 255)
                }
            }
        }
        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(multiArray: input)]))
        guard let output = prediction.featureValue(for: "skinClasses")?.multiArrayValue,
              output.shape.map(\.intValue) == [1, 256, 256, 6] else { throw OnDeviceAnalysis.AnalysisError.invalidMask }
        var alpha = [UInt8](repeating: 0, count: side * side)
        for y in top...bottom {
            for x in left...right {
                let px = min(255, (x - left) * 256 / w), py = min(255, (y - top) * 256 / h)
                let index = (py * 256 + px) * 6
                let logits = (0..<6).map { output[index + $0].doubleValue }
                guard logits.allSatisfy({ $0.isFinite }), let maximum = logits.max() else {
                    throw OnDeviceAnalysis.AnalysisError.invalidMask
                }
                let probabilities = logits.map { exp($0 - maximum) }
                let denominator = probabilities.reduce(0, +)
                let skin = (probabilities[2] + probabilities[3]) / denominator
                alpha[y * side + x] = UInt8((min(1, max(0, skin)) * Double(person.alpha[y * side + x])).rounded())
            }
        }
        return .init(side: side, alpha: alpha)
    }

    enum SelectionError: Error, LocalizedError {
        case modelMissing, tooManyPeople
        var errorDescription: String? {
            switch self {
            case .modelMissing: "This build is missing its masking model. Reinstall the complete app build."
            case .tooManyPeople: "This photo contains more than 20 detected people. Crop a smaller group before creating separate masks."
            }
        }
    }
}
