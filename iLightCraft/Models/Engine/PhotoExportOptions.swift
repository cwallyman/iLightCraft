//
//  PhotoExportOptions.swift
//  iLightCraft
//

/// Native export options use the shared engine's command parameter names.
nonisolated struct PhotoExportOptions: Encodable, Sendable {

    var format = "jpeg"
    var quality = 92
    var longEdge = 0
    var colorSpace = "srgb"
    var bitDepth = 8
    var metadata = "all"
    var removeLocation = false
    var sharpen = "none"
    var sharpenAmount = "standard"
    var watermark = ""
    var hdr = false

    enum CodingKeys: String, CodingKey {
        case format, quality, longEdge, colorSpace, bitDepth, metadata, removeLocation, sharpen, sharpenAmount, watermark
    }

    var fileExtension: String { format == "jpeg" ? "jpg" : (format == "tiff" ? "tif" : (format == "heic" ? "heic" : "png")) }
}
