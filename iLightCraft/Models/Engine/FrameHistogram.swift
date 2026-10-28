//
//  FrameHistogram.swift
//  iLightCraft
//

import Foundation

// nonisolated: the engine thread builds it, and the adjust card reads it on the main actor.
/// FrameHistogram is the engine's histogram of one whole-frame preview (uv.h `UVHistogram`): 256
/// bins each for red, green, blue and luminance over `total` sampled pixels, and the sampled
/// pixels at 0 and at 255 per channel. It always describes the whole photo: a zoom window carries
/// one only when asked, from a small whole frame of the same look. `generation` and `isDraft` are
/// the frame's, so the card can tell a drag frame from the full preview that settles it.
nonisolated struct FrameHistogram: Equatable, Sendable {

    let red        : [UInt32]
    let green      : [UInt32]
    let blue       : [UInt32]
    let luma       : [UInt32]
    let total      : Int
    let clippedLow : [Int]       // Pixels at 0 in R, G, B.
    let clippedHigh: [Int]       // Pixels at 255 in R, G, B.
    let generation : UInt64
    let isDraft    : Bool

    /// clippingThreshold is the share of pixels at an end, in any one channel, from which that end
    /// counts as clipped: 0.1 %, so a few specular highlights or a black border do not light it.
    static let clippingThreshold = 0.001

    /// shadowClipping and highlightClipping are the largest share of pixels at 0 (at 255) in one
    /// channel: a lower bound of the share clipped in any channel, which the overlay shows exactly.
    var shadowClipping   : Double { share(clippedLow) }
    var highlightClipping: Double { share(clippedHigh) }

    var isShadowClipped   : Bool { shadowClipping > Self.clippingThreshold }
    var isHighlightClipped: Bool { highlightClipping > Self.clippingThreshold }

    /// shadowChannels and highlightChannels are which of R, G, B clip at that end, using per-channel indicators:
    /// each channel above the threshold, or all three when luminance itself reaches the end bin
    /// (true black or white, not one saturated primary).
    var shadowChannels   : [Bool] { channels(clippedLow, lumaBin: 0) }
    var highlightChannels: [Bool] { channels(clippedHigh, lumaBin: 255) }

    /// clippingSummary says in words what the clipping indicators show, for VoiceOver.
    var clippingSummary: String {
        "\(Self.words(for: "Shadows", channels: shadowChannels, share: shadowClipping)); "
            + Self.words(for: "highlights", channels: highlightChannels, share: highlightClipping)
    }

    /// words(for:channels:share:) is one end in words: "Shadows clipped in blue, 2.1 %", "in all
    /// channels" when all three clip, "Shadows not clipped" when none does.
    static func words(for end: String, channels: [Bool], share: Double) -> String {
        let names = zip(["red", "green", "blue"], channels).filter(\.1).map(\.0)

        guard !names.isEmpty else { return "\(end) not clipped" }

        let which   = names.count == 3 ? "all channels" : names.joined(separator: " and ")
        let percent = share.formatted(.percent.precision(.fractionLength(0 ... 1)))

        return "\(end) clipped in \(which), \(percent)"
    }

    private func share(_ counts: [Int]) -> Double {
        guard total > 0 else { return 0 }

        return Double(counts.max() ?? 0) / Double(total)
    }

    private func channels(_ counts: [Int], lumaBin: Int) -> [Bool] {
        guard total > 0 else { return [false, false, false] }

        let threshold = Self.clippingThreshold * Double(total)

        if luma.indices.contains(lumaBin), Double(luma[lumaBin]) > threshold {
            return [true, true, true]
        }

        return counts.map { Double($0) > threshold }
    }
}
