//
//  HistogramView.swift
//  Unveil
//

import SwiftUI

/// HistogramView heads the adjust card: the photo's histogram, the two clipping toggles on its top
/// corners and, below, the exposure the file records.
///
/// Red, green and blue are drawn as translucent fills that add up where they overlap (yellow, cyan,
/// magenta, white), over a dark well so they read the same on light and dark glass, with luminance
/// as a neutral outline. Heights follow the square root of the counts, so the midtones stay legible
/// next to a tall peak, scaled to the tallest bin away from the two ends: a clipped end may run off
/// the top, which is what the toggles are for.
///
/// A drag's draft frames redraw the plot in place; the full preview that settles it cross-fades in
/// (not under Reduce Motion). VoiceOver reads the plot as one element that says what is clipped.
///
/// It is the only view that reads the view model's histogram, so a draft frame re-evaluates this
/// view alone, not the card around it.
struct HistogramView<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>

    @Binding
    var clipping: ClippingOverlay

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    private let plotHeight  : CGFloat = 64
    private let cornerRadius: CGFloat = 12

    var body: some View {
        let histogram = viewModel.histogram

        VStack(alignment: .leading, spacing: 8) {

            plot(histogram)
                .overlay(alignment: .topLeading) {
                    ClippingToggle(
                        end      : .shadows,
                        channels : histogram?.shadowChannels ?? [false, false, false],
                        share    : histogram?.shadowClipping ?? 0,
                        clipping : $clipping
                    )
                }
                .overlay(alignment: .topTrailing) {
                    ClippingToggle(
                        end      : .highlights,
                        channels : histogram?.highlightChannels ?? [false, false, false],
                        share    : histogram?.highlightClipping ?? 0,
                        clipping : $clipping
                    )
                }

            if let capture = viewModel.captureSummary {
                Text(capture)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// plot keys the drawing by `fadeKey(of:)`: drafts share one identity and redraw in place, and
    /// each full preview gets its own, which is what cross-fades.
    private func plot(_ histogram: FrameHistogram?) -> some View {
        ZStack {
            if let histogram {
                HistogramPlot(histogram: histogram)
                    .id(Self.fadeKey(of: histogram))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: plotHeight)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: cornerRadius))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .animation(fade(to: histogram), value: histogram.map(Self.fadeKey))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Histogram")
        .accessibilityValue(histogram?.clippingSummary ?? "No photo")
        .accessibilityIdentifier("histogram")
    }

    /// fadeKey is 0 for every draft and the generation for a full preview.
    private static func fadeKey(of histogram: FrameHistogram) -> UInt64 {
        histogram.isDraft ? 0 : histogram.generation
    }

    /// fade(to:) is the cross-fade to a full preview's histogram: none to a draft (the key also
    /// changes on a drag's first draft) and none under Reduce Motion.
    private func fade(to histogram: FrameHistogram?) -> Animation? {
        guard let histogram, !histogram.isDraft, !reduceMotion else { return nil }

        return .easeInOut(duration: 0.2)
    }
}
