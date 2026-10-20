//
//  NativeImageInfo.swift
//  Unveil
//

import Foundation

/// Durable provenance for an Apple-decoded editing copy. The original remains beside it, unchanged.
nonisolated struct NativeImageInfo: Codable, Sendable {

    let originalFileName: String
    let rawDecoderVersion: String?
    let hdr: Bool

    static func read(for url: URL) throws -> NativeImageInfo? {
        let metadata = url.appendingPathExtension("native.json")
        guard FileManager.default.fileExists(atPath: metadata.path) else { return nil }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: metadata))
    }
}
