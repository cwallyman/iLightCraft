import Foundation

nonisolated enum HSLColorBand: String, CaseIterable, Identifiable, Sendable {
    case red, orange, yellow, green, aqua, blue, purple, magenta
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var controls: [DevelopAdjustmentKind] {
        ["hue", "sat", "lum"].compactMap { DevelopAdjustmentKind(rawValue: "mixer.\(rawValue).\($0)") }
    }
}
