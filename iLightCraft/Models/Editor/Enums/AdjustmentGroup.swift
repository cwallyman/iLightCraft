//
//  AdjustmentGroup.swift
//  iLightCraft
//

/// AdjustmentGroup names the sets of develop controls shown in the adjust card, one carousel page
/// each. Case order is the page order, and the raw value the page index.
nonisolated enum AdjustmentGroup: Int, CaseIterable, Identifiable, Sendable {

    case light
    case color
    case presence
    case detail
    case effects

    var id: Int { rawValue }

    /// title is the name shown in the page strip and the page header.
    var title: String {
        switch self {
            case .light:    "Light"
            case .color:    "Color"
            case .presence: "Presence"
            case .detail:   "Detail"
            case .effects:  "Effects"
        }
    }

    /// swipeThreshold is how far a swipe on the page strip has to travel to change page.
    static let swipeThreshold: Double = 30

    /// next is the page after this one in the card's carousel; the last page stays where it is.
    var next: AdjustmentGroup { Self(rawValue: rawValue + 1) ?? self }

    /// previous is the page before this one; the first page stays where it is.
    var previous: AdjustmentGroup { Self(rawValue: rawValue - 1) ?? self }

    /// swiped(by:) is the page a horizontal swipe of `translation` points lands on. A swipe to the
    /// left brings the next page in from the trailing side, as a finger pushing the strip would.
    func swiped(by translation: Double) -> AdjustmentGroup {
        if translation <= -Self.swipeThreshold { return next }
        if translation >= Self.swipeThreshold  { return previous }

        return self
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
