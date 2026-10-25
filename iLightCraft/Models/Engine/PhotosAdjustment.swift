//
//  PhotosAdjustment.swift
//  iLightCraft
//

import Foundation

/// Complete engine settings travel with the same Photos asset; unsupported envelopes are never applied.
nonisolated struct PhotosAdjustment: Codable, Sendable {

    static let identifier = "com.cwallyman.iLightCraft.develop"
    static let formatVersion = "1"
    static func canRead(_ identifier: String) -> Bool {
        identifier == Self.identifier || identifier == LegacyEditCompatibility.photosIdentifier
    }
    let schema: Int
    let engine: String
    let settings: Data
    let rawDecoderVersion: String?

    init(settings: Data, rawDecoderVersion: String?) throws {
        try Self.validate(settings)
        schema = 1
        engine = "ilightcraft-native-hdr-1"
        self.settings = settings
        self.rawDecoderVersion = rawDecoderVersion
    }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 24 * 1024 * 1024 else { throw PhotoLibraryError.invalidAdjustment }
        let value = try JSONDecoder().decode(Self.self, from: data)
        guard value.schema == 1, (value.engine == "ilightcraft-native-hdr-1" || value.engine == LegacyEditCompatibility.engineVersion) else { throw PhotoLibraryError.invalidAdjustment }
        try validate(value.settings)
        return value
    }

    private static func validate(_ data: Data) throws {
        guard data.count <= 16 * 1024 * 1024,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = object["version"] as? Int, version == 1 else {
            throw PhotoLibraryError.invalidAdjustment
        }
    }
}
