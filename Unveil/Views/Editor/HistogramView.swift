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
/// The plot never fades: it glides toward each new histogram, a drag's drafts and the full preview
/// that settles a release alike (HistogramEasing), stepped by a TimelineView that runs only while
/// the glide moves. Under Reduce Motion each histogram shows at once. VoiceOver reads the plot as
/// one element that says what is clipped.
///
/// It is the only view that reads the view model's histogram, so a draft frame re-evaluates this
/// view alone, not the card around it; a glide's frames re-evaluate only the timeline's plot.
struct HistogramView<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>

    @Binding
    var clipping: ClippingOverlay

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @State
    private var motion = HistogramMotion()

    /// isGliding runs the plot's timeline; the glide's last step turns it off.
    @State
    private var isGliding = false

    /// plotAspect is the plot's width over its height.
    private let plotAspect  : CGFloat = 3
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

    /// plot steps the glide on each tick of its timeline, paused while the glide rests, and follows
    /// every new histogram (see the type doc).
    private func plot(_ histogram: FrameHistogram?) -> some View {
        ZStack {
            // Gives the plot its size before the first histogram arrives.
            Color.clear

            if histogram != nil {
                TimelineView(.animation(paused: !isGliding)) { timeline in
                    let easing = FrameTimingProbe.shared.measure("HistogramGlide") {
                        motion.advanced(
                            toward    : histogram,
                            at        : timeline.date.timeIntervalSinceReferenceDate,
                            instantly : reduceMotion
                        )
                    }

                    HistogramPlot(levels: easing.levels)
                        .onChange(of: easing.isMoving) { _, isMoving in
                            if !isMoving { isGliding = false }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(plotAspect, contentMode: .fit)
        .background(.black.opacity(0.35), in: .rect(cornerRadius: cornerRadius))
        .clipShape(.rect(cornerRadius: cornerRadius))
        .onChange(of: histogram?.generation, initial: true) {
            isGliding = motion.aim(
                at        : histogram,
                from      : Date.now.timeIntervalSinceReferenceDate,
                instantly : reduceMotion
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Histogram")
        .accessibilityValue(histogram?.clippingSummary ?? "No photo")
        .accessibilityIdentifier("histogram")
    }
}

/// HistogramMotion holds the glide across the timeline's ticks. It is a plain class, not observed:
/// stepping it must not invalidate anything, the timeline alone redraws the plot.
///
/// A new histogram can reach the timeline's content before the view's `onChange` runs, so both aim
/// through `aim`, which retargets once per frame generation, whichever comes first.
@MainActor
private final class HistogramMotion {

    private var easing = HistogramEasing()
    private var aimedAt: UInt64?

    /// aim retargets the glide at `histogram` unless it already aims there, and says if it moves.
    @discardableResult
    func aim(at histogram: FrameHistogram?, from time: Double, instantly: Bool) -> Bool {
        if histogram?.generation != aimedAt {
            aimedAt = histogram?.generation
            easing.retarget(to: histogram, at: time, instantly: instantly)
        }

        return easing.isMoving
    }

    func advanced(toward histogram: FrameHistogram?, at time: Double, instantly: Bool) -> HistogramEasing {
        // A paused timeline's date is the pause's: a glide starts from now.
        aim(at: histogram, from: Date.now.timeIntervalSinceReferenceDate, instantly: instantly)
        easing.advance(to: time)

        return easing
    }
}
