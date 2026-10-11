//
//  ClippingToggle.swift
//  Unveil
//

import SwiftUI

/// ClippingToggle is one of the histogram's corner triangles, Lightroom style: lit in the colour of
/// the channels that clip at its end (their additive mix, white when all three do), dim when none
/// does. It toggles the canvas overlay that marks those pixels (blue for shadows, red for
/// highlights), ringed in that colour while on. The triangle is small; its touch target is 44 pt.
struct ClippingToggle: View {

    let end      : ClippingOverlay
    let channels : [Bool]            // R, G, B clipping at this end (FrameHistogram).
    let share    : Double

    @Binding
    var clipping: ClippingOverlay

    private var isOn: Bool { clipping.contains(end) }

    private var isShadows: Bool { end == .shadows }

    private var isClipped: Bool { channels.contains(true) }

    var body: some View {
        Button {
            clipping.formSymmetricDifference(end)
        } label: {
            Image(systemName: "triangle.fill")
                .font(.system(size: 9, weight: .bold))
                .rotationEffect(.degrees(isShadows ? -45 : 45))
                .foregroundStyle(isClipped ? lit : .white.opacity(0.35))
                .frame(width: 20, height: 20)
                .background(isOn ? .white.opacity(0.2) : .clear, in: .circle)
                .overlay {
                    if isOn {
                        Circle().strokeBorder(tint, lineWidth: 2)
                    }
                }
                .padding(4)
                .frame(width: 44, height: 44, alignment: isShadows ? .topLeading : .topTrailing)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityLabel(isShadows ? "Show Shadow Clipping" : "Show Highlight Clipping")
        .accessibilityValue(
            FrameHistogram.words(for: isShadows ? "Shadows" : "Highlights", channels: channels, share: share)
        )
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(isShadows ? "shadow-clipping" : "highlight-clipping")
    }

    /// tint is the overlay's colour for this end, the ring shown while it is on.
    private var tint: Color {
        isShadows ? .blue : .red
    }

    /// lit mixes the clipped channels' primaries additively: one primary, yellow, cyan, magenta or white.
    private var lit: Color {
        let level = { (index: Int) in channels.indices.contains(index) && channels[index] ? 1.0 : 0.0 }

        return Color(red: level(0), green: level(1), blue: level(2))
    }
}
