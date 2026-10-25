//
//  PhotoEditContext.swift
//  iLightCraft
//

import Foundation

/// The Photos revision an editing copy was based on. Never refreshed merely to bypass a conflict.
nonisolated struct PhotoEditContext: Codable, Equatable, Sendable {

    let assetIdentifier: String
    var revision: String
    let sourceFile: String
    var initialSettings: Data?
    var rawDecoderVersion: String?
    var displayName: String? = nil
    var sourceIsRAW: Bool? = nil

    static func read(for source: URL) throws -> Self? {
        let url = source.appendingPathExtension("photos.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let value = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard value.sourceFile == URL(filePath: value.sourceFile).lastPathComponent,
              ![".", ".."].contains(value.sourceFile) else { throw PhotoLibraryError.invalidAdjustment }
        return value
    }
}
