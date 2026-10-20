//
//  CropSettings.swift
//  Unveil
//

import CoreGraphics

/// The geometry subset of develop settings, restored together as one native undo step.
nonisolated struct CropSettings: Codable, Equatable, Sendable {

    var crop = Crop()
    var orientation = "Normal"

    struct Crop: Codable, Equatable, Sendable {

        var geometry = Geometry()
        var aspect: [UInt32]?
        var flip_h = false
        var flip_v = false

        enum CodingKeys: String, CodingKey { case geometry, aspect, flip_h, flip_v }

        /// A free crop must explicitly clear a previous aspect lock when merged into engine settings.
        func encode(to encoder: Encoder) throws {
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(geometry, forKey: .geometry)
            try fields.encode(aspect, forKey: .aspect)
            try fields.encode(flip_h, forKey: .flip_h)
            try fields.encode(flip_v, forKey: .flip_v)
        }
    }

    struct Geometry: Codable, Equatable, Sendable {

        var rect = Rectangle()
        var angle = 0.0
    }

    struct Rectangle: Codable, Equatable, Sendable {

        var x0 = 0.0
        var y0 = 0.0
        var x1 = 1.0
        var y1 = 1.0

        var cgRect: CGRect { CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0) }

        init() {}

        init(_ rect: CGRect) {
            x0 = Double(rect.minX)
            y0 = Double(rect.minY)
            x1 = Double(rect.maxX)
            y1 = Double(rect.maxY)
        }
    }

    mutating func rotate(clockwise: Bool) {
        let normal = ["Normal", "Rotate90", "Rotate180", "Rotate270"]
        let flipped = ["FlipH", "Transverse", "FlipV", "Transpose"]
        let sequence = normal.contains(orientation) ? normal : flipped
        let index = sequence.firstIndex(of: orientation) ?? 0
        orientation = sequence[(index + (clockwise ? 1 : 3)) % 4]
        crop.geometry.rect = .init()
        crop.aspect = nil
    }
}
