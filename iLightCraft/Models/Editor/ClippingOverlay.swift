//
//  ClippingOverlay.swift
//  iLightCraft
//

/// ClippingOverlay is which clipped pixels the canvas marks: shadows (0 in any channel) in blue,
/// highlights (255 in any channel) in red. The raw value is the bit mask Canvas.metal reads.
nonisolated struct ClippingOverlay: OptionSet, Equatable, Sendable {

    let rawValue: UInt32

    static let shadows    = ClippingOverlay(rawValue: 1 << 0)
    static let highlights = ClippingOverlay(rawValue: 1 << 1)
}
