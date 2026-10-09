//
//  AdjustmentGroup.swift
//  Unveil
//

/// AdjustmentGroup is one panel of the editor's toolbar: a named set of develop controls.
///
/// The order of the cases is the order of the segments, left to right, and the toolbar uses it to
/// pick the direction a panel slides in when the user switches from one group to another.
nonisolated enum AdjustmentGroup: Int, CaseIterable, Identifiable, Sendable {

    case light
    case color
    case presence
    case detail
    case effects

    var id: Int { rawValue }

    /// title is the segment label, in Italian like the rest of the editor.
    var title: String {
        switch self {
            case .light:    "Luce"
            case .color:    "Colore"
            case .presence: "Presenza"
            case .detail:   "Dettaglio"
            case .effects:  "Effetti"
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
