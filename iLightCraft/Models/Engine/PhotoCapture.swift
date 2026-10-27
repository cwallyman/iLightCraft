//
//  PhotoCapture.swift
//  iLightCraft
//

import Foundation
import ImageIO

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

    static let empty = PhotoCapture(iso: nil, shutter: nil, aperture: nil, focalMM: nil)

    /// displayValues always reserves the four capture fields, even when metadata is absent.
    var displayValues: [String] {
        [iso.flatMap { $0 > 0 ? "ISO \($0)" : nil } ?? "ISO —",
         Self.positive(focalMM).map { "\(Self.trimmed($0)) mm" } ?? "— mm",
         Self.positive(aperture).map { "f/\(Self.trimmed($0))" } ?? "f/—",
         shutter.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : "\($0) s" } ?? "— s"]
    }

    func merging(_ fallback: PhotoCapture?) -> PhotoCapture {
        PhotoCapture(iso: iso.flatMap { $0 > 0 ? $0 : nil } ?? fallback?.iso,
                     shutter: shutter.flatMap { $0.isEmpty ? nil : $0 } ?? fallback?.shutter,
                     aperture: Self.positive(aperture) ?? fallback?.aperture,
                     focalMM: Self.positive(focalMM) ?? fallback?.focalMM)
    }

    /// read fills gaps from the preserved original for Apple-decoded editing copies.
    static func read(from editingURL: URL) -> PhotoCapture? {
        var sourceURL = editingURL
        if let info = try? NativeImageInfo.read(for: editingURL) {
            let name = info.originalFileName
            if !name.isEmpty, name != ".", name != "..", !name.contains("/"), !name.contains("\\") {
                sourceURL = editingURL.deletingLastPathComponent().appendingPathComponent(name)
            }
        }
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] else { return nil }
        func number(_ key: CFString) -> Double? { Self.positive((exif[key] as? NSNumber)?.doubleValue) }
        let sensitivity = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first?.doubleValue
        let iso = sensitivity.flatMap { $0.isFinite && $0 >= 1 && $0 <= 1_000_000_000 ? Int($0.rounded()) : nil }
        var exposure = number(kCGImagePropertyExifExposureTime)
        if exposure == nil, let apex = (exif[kCGImagePropertyExifShutterSpeedValue] as? NSNumber)?.doubleValue, apex.isFinite {
            exposure = Self.positive(pow(2, -apex))
        }
        let shutter = exposure.map { seconds -> String in
            let reciprocal = 1 / seconds
            if seconds < 1, reciprocal.isFinite, reciprocal <= 1_000_000_000,
               abs(reciprocal - reciprocal.rounded()) / reciprocal < 0.02 {
                return String(format: "1/%.0f", locale: Self.posix, reciprocal)
            }
            return seconds.formatted(.number.precision(.fractionLength(0...4)).grouping(.never).locale(Self.posix))
        }
        return PhotoCapture(iso: iso, shutter: shutter, aperture: number(kCGImagePropertyExifFNumber), focalMM: number(kCGImagePropertyExifFocalLength))
    }

    private static func positive(_ value: Double?) -> Double? {
        value.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    /// trimmed writes at most one decimal and drops a trailing ".0": f/2.8, f/8, 35 mm.
    private static func trimmed(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0 ... 1)).grouping(.never).locale(Self.posix))
    }
}
