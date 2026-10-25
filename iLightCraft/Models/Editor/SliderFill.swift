//
//  SliderFill.swift
//  iLightCraft
//

/// SliderFill is the filled part of a slider track, as fractions of the track's length (0 is the
/// lower bound, 1 the upper one), plus where the thumb sits.
///
/// A centred control (a range that goes below zero, such as Contrast or Tint) fills from its
/// default toward the thumb, so a negative value fills to the left of the default and the fill
/// is empty at the default. Every other control (Temperature, Sharpening, Grain) fills from the
/// lower bound. The default is the photo's own one, so a raw's as-shot Tint is the fill's origin.
nonisolated struct SliderFill: Equatable, Sendable {

    let start: Double
    let end  : Double
    let thumb: Double

    init(
        value       : Double,
        range       : ClosedRange<Double>,
        defaultValue: Double
    ) {
        let origin = range.lowerBound < 0 ? defaultValue : range.lowerBound
        let thumb  = Self.fraction(of: value, in: range)
        let anchor = Self.fraction(of: origin, in: range)

        self.start = min(anchor, thumb)
        self.end   = max(anchor, thumb)
        self.thumb = thumb
    }

    /// fraction(of:in:) places `value` along the track, clamped to it. An empty range sits at 0.
    static func fraction(of value: Double, in range: ClosedRange<Double>) -> Double {
        let span = range.upperBound - range.lowerBound

        guard span > 0 else { return 0 }

        return min(max((value - range.lowerBound) / span, 0), 1)
    }
}
