//
//  LocalAnalysisIndex.swift
//  iLightCraft
//

import Foundation

/// LocalAnalysisIndex stores model labels and OCR only in the app's private library workspace.
nonisolated struct LocalAnalysisIndex: Codable, Sendable {
    struct Entry: Codable, Identifiable, Sendable {
        let id: UInt64
        let name: String
        let indexedAt: Date
        let analysis: OnDeviceAnalysis.Description
    }
    var version = 1
    var entries: [Entry] = []
    static let url = URL.applicationSupportDirectory.appending(path: "Analysis/local-index.json")
    static func load() throws -> Self {
        guard FileManager.default.fileExists(atPath: url.path) else { return Self() }
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= 32 * 1024 * 1024 else { throw IndexError.invalidCache }
        let index = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard index.version == 1, index.entries.count <= 1000 else { throw IndexError.invalidCache }
        return index
    }
    mutating func record(id: UInt64, name: String, analysis: OnDeviceAnalysis.Description) throws {
        entries.removeAll { $0.id == id }
        guard entries.count < 1000 else { throw IndexError.full }
        entries.append(Entry(id: id, name: String(name.prefix(256)), indexedAt: .now, analysis: analysis))
    }
    func save() throws {
        let data = try JSONEncoder().encode(self)
        guard data.count <= 32 * 1024 * 1024 else { throw IndexError.full }
        try FileManager.default.createDirectory(at: Self.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: Self.url, options: .atomic)
    }
    func search(_ query: String) -> [Entry] {
        let ignored: Set<String> = ["a", "an", "the", "of", "with", "show", "me", "photos", "pictures", "images", "and", "in", "at"]
        let terms = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { !ignored.contains($0) }
        let queryVector = terms.isEmpty ? nil : LocalSemanticSearch.vector(for: query)
        return entries.compactMap { entry -> (Entry, Double)? in
            let text = ([entry.name] + entry.analysis.labels + entry.analysis.text).joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let exact = terms.allSatisfy { term in
                if ["people", "person", "face", "faces"].contains(term) { return entry.analysis.faces > 0 }
                if term == "text" { return !entry.analysis.text.isEmpty }
                return text.contains(term)
            }
            if exact { return (entry, 2) }
            if let queryVector, let vector = entry.analysis.embedding,
               let score = LocalSemanticSearch.similarity(queryVector, vector), score >= 0.55 { return (entry, score) }
            return nil
        }.sorted { first, second in
            first.1 == second.1 ? first.0.indexedAt > second.0.indexedAt : first.1 > second.1
        }.map(\.0)
    }

    enum IndexError: Error, LocalizedError {
        case full, invalidCache
        var errorDescription: String? {
            switch self {
            case .full: "The local analysis index reached its current 1,000-photo or 32 MB limit."
            case .invalidCache: "The private analysis index is invalid or unsupported. It was retained for recovery."
            }
        }
    }
}
