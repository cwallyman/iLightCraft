//
//  AdjustmentGroup.swift
//  Unveil
//

/// AdjustmentGroup names the sets of develop controls shown in the adjust card.
/// Case order determines the order of the group picker.
nonisolated enum AdjustmentGroup: Int, CaseIterable, Identifiable, Sendable {

    case light
    case color
    case presence
    case detail
    case effects

    var id: Int { rawValue }

    /// title is the name shown in the group picker and the section heading.
    var title: String {
        switch self {
            case .light:    "Light"
            case .color:    "Color"
            case .presence: "Presence"
            case .detail:   "Detail"
            case .effects:  "Effects"
        }
    }

    /// kinds are the controls the panel shows, in panel order.
    var kinds: [DevelopAdjustmentKind] {
        switch self {
            case .light:    [.exposure, .contrast, .highlights, .shadows, .whites, .blacks]
            case .color:    [.temperature, .tint, .vibrance, .saturation]
            case .presence: [.texture, .clarity, .dehaze]
            case .detail:   [.sharpening, .noiseReduction, .colorNoise]
            case .effects:  [.vignette, .grain]
        }
    }
}
