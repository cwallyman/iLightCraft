//
//  PhotoCapture.swift
//  iLightCraft
//

import Foundation

/// PhotoCapture is the exposure part of `photo.inspect`'s `meta` (the catalog `Meta`): what the
/// adjust card shows under the histogram. The engine writes an empty shutter and leaves the numbers
/// out when the file does not record them, and the summary omits those.
nonisolated struct PhotoCapture: Decodable, Equatable, Sendable {

    let iso     : Int?
    let shutter : String?           // "1/250" below a second, else whole seconds ("2").
    let aperture: Double?
    let focalMM : Double?

    enum CodingKeys: String, CodingKey {

        case iso
        case shutter
        case aperture
        case focalMM = "focal_mm"
    }

    /// summary is the known values as a photographer reads them, "ISO 200 · 1/250 s · f/2.8 ·
    /// 35 mm", or nil when the file records none.
    var summary: String? {
        let parts = [
            iso.map { "ISO \($0)" },
            shutter.flatMap { $0.isEmpty ? nil : "\($0) s" },
            aperture.map { "f/\(Self.trimmed($0))" },
            focalMM.map { "\(Self.trimmed($0)) mm" },
        ].compactMap(\.self)

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// trimmed writes at most one decimal and drops a trailing ".0": f/2.8, f/8, 35 mm.
    private static func trimmed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)).grouping(.never).locale(Self.posix))
    }
}
