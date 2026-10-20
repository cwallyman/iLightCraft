//
//  LocalSemanticSearch.swift
//  Unveil
//

import Foundation
import NaturalLanguage

/// LocalSemanticSearch embeds indexed labels/OCR locally; it is not a joint image-text model.
nonisolated enum LocalSemanticSearch {
    static func vector(for text: String) -> [Double]? {
        guard !text.isEmpty, let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = embedding.vector(for: String(text.prefix(4096))),
              vector.count <= 2048, vector.allSatisfy(\.isFinite) else { return nil }
        return vector
    }
    static func similarity(_ first: [Double], _ second: [Double]) -> Double? {
        guard !first.isEmpty, first.count == second.count, first.count <= 2048 else { return nil }
        var product = 0.0, firstLength = 0.0, secondLength = 0.0
        for (a, b) in zip(first, second) {
            guard a.isFinite, b.isFinite else { return nil }
            product += a * b; firstLength += a * a; secondLength += b * b
        }
        let denominator = (firstLength * secondLength).squareRoot()
        guard denominator.isFinite, denominator > 0, product.isFinite else { return nil }
        return min(1, max(-1, product / denominator))
    }
}
