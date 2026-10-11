//
//  SliderSpeed.swift
//  Unveil
//

import CoreGraphics

/// SliderSpeed is the precision band of a slider drag. The farther the finger moves vertically
/// away from the track, the less a horizontal move changes the value: full speed close to the
/// track, then half, quarter and an eighth ("Fine"), one band every 44 pt (a touch target).
nonisolated enum SliderSpeed: CaseIterable, Sendable {

    case full
    case half
    case quarter
    case fine

    /// bandHeight is how far each band reaches, measured from the track's center line.
    static let bandHeight: CGFloat = 44

    /// init(distance:) picks the band for the finger's vertical distance from the track. Each
    /// boundary belongs to the slower band: exactly 44 pt is already half speed.
    init(distance: CGFloat) {
        switch abs(distance) {
            case ..<Self.bandHeight:         self = .full
            case ..<(Self.bandHeight * 2):   self = .half
            case ..<(Self.bandHeight * 3):   self = .quarter
            default:                         self = .fine
        }
    }

    /// factor scales the finger's horizontal motion before it becomes a value change.
    var factor: Double {
        switch self {
            case .full:    1
            case .half:    0.5
            case .quarter: 0.25
            case .fine:    0.125
        }
    }

    /// label is the capsule shown near the row while dragging, nil at full speed.
    var label: String? {
        switch self {
            case .full:    nil
            case .half:    "Half Speed"
            case .quarter: "Quarter Speed"
            case .fine:    "Fine"
        }
    }
}
