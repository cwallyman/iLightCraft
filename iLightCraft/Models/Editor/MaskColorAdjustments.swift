import Foundation

/// Only the exposed local fields are sent: mask.adjust deep-merges them and preserves
/// other saved local settings. Old exposure-only native fixtures decode to neutral color.
nonisolated struct MaskColorAdjustments: Codable, Equatable, Sendable {
    var exposure = 0.0
    var contrast = 0.0
    var highlights = 0.0
    var shadows = 0.0
    var whites = 0.0
    var blacks = 0.0
    var texture = 0.0
    var clarity = 0.0
    var dehaze = 0.0
    var sharpness = 0.0
    var noise = 0.0

    var temperature = 0.0
    var tint = 0.0
    var hue = 0.0
    var saturation = 0.0
    var colorHue = 0.0
    var colorAmount = 0.0

    enum CodingKeys: String, CodingKey {
        case exposure, tint, hue, saturation, contrast, highlights, shadows, whites, blacks, texture, clarity, dehaze, sharpness, noise
        case temperature = "temp", colorHue = "color_hue", colorAmount = "color_sat"
    }
    init() {}
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try fields.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        temperature = try fields.decodeIfPresent(Double.self, forKey: .temperature) ?? 0
        tint = try fields.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        hue = try fields.decodeIfPresent(Double.self, forKey: .hue) ?? 0
        saturation = try fields.decodeIfPresent(Double.self, forKey: .saturation) ?? 0
        colorHue = try fields.decodeIfPresent(Double.self, forKey: .colorHue) ?? 0
        colorAmount = try fields.decodeIfPresent(Double.self, forKey: .colorAmount) ?? 0
        contrast = try fields.decodeIfPresent(Double.self, forKey: .contrast) ?? 0
        highlights = try fields.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        shadows = try fields.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        whites = try fields.decodeIfPresent(Double.self, forKey: .whites) ?? 0
        blacks = try fields.decodeIfPresent(Double.self, forKey: .blacks) ?? 0
        texture = try fields.decodeIfPresent(Double.self, forKey: .texture) ?? 0
        clarity = try fields.decodeIfPresent(Double.self, forKey: .clarity) ?? 0
        dehaze = try fields.decodeIfPresent(Double.self, forKey: .dehaze) ?? 0
        sharpness = try fields.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0
        noise = try fields.decodeIfPresent(Double.self, forKey: .noise) ?? 0
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Mask color settings are invalid"))
        }
    }
    var isValid: Bool {
        [exposure, temperature, tint, hue, saturation, colorHue, colorAmount].allSatisfy(\.isFinite)
            && (-4...4).contains(exposure)
            && [temperature, tint, hue, saturation, contrast, highlights, shadows, whites, blacks, texture, clarity, dehaze, sharpness, noise].allSatisfy { (-100...100).contains($0) }
            && (0...360).contains(colorHue) && (0...100).contains(colorAmount)
    }
    mutating func colorize(hue: Double) {
        guard hue.isFinite else { return }
        colorHue = min(360, max(0, hue))
        colorAmount = 100
        // Neutralize existing chroma before applying the chosen hue. The engine retains lightness.
        saturation = -100
    }
    mutating func resetColor() {
        temperature = 0; tint = 0; hue = 0; saturation = 0; colorHue = 0; colorAmount = 0
    }
}
