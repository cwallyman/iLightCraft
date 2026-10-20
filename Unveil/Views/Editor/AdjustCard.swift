//
//  AdjustCard.swift
//  Unveil
//

import SwiftUI

/// AdjustCard is the docked editing panel beside or below the photo: the photo's histogram with its
/// clipping toggles, a carousel of one page per AdjustmentGroup, and at the bottom a strip that
/// names the pages. The histogram stays put while the pages slide under it.
///
/// The card is as tall as its tallest page (Light), up to the space it is offered, so it hugs
/// its content and does not change height mid-slide. The strip sits in its own darker capsule,
/// a fill inside the card; the card's glass itself stays untinted.
///
/// Only the strip changes page (a tap on a name, or a swipe left or right on it); the sliders'
/// area has no paging gesture, so a slider drag can never turn the page. The pages sit on top of
/// each other, each offset by its distance from the selected one and faded, so a change slides in
/// the swipe's direction whichever page it comes from. Under Reduce Motion they only cross-fade.
/// Pages that are not selected take no touches and are hidden from VoiceOver.
///
/// The selected page is the session's `selectedGroup`, bound in, so `-UnveilPanel` still opens
/// the card on a given page.
struct AdjustCard<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>

    @Binding
    var group: AdjustmentGroup

    /// clipping is the session's clipping overlay, toggled from the histogram's corners.
    @Binding
    var clipping: ClippingOverlay

    var width               : CGFloat = 340
    var showsHistogram      : Bool = true
    var isCompact           : Bool = false
    var histogramHeight     : CGFloat? = nil
    private let cornerRadius: CGFloat = 28

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.colorScheme)
    private var colorScheme

    @Namespace
    private var strip

    var body: some View {
        VStack(spacing: 0) {

            if showsHistogram {
                HistogramView(
                    viewModel          : viewModel,
                    clipping           : $clipping,
                    fixedPlotHeight    : histogramHeight,
                    showsCaptureSummary: !isCompact
                )
                    .padding(.horizontal, 16)
                    .padding(.top, isCompact ? 10 : 16)
            }

            pages

            pageStrip
        }
        .frame(width: width)
        .clipShape(.rect(cornerRadius: cornerRadius))
        .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.3), value: group)
        .sensoryFeedback(.selection, trigger: group)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adjustments")
        .accessibilityIdentifier("adjust-card")
    }

    private var pages: some View {
        ZStack(alignment: .top) {

            ForEach(AdjustmentGroup.allCases) { page in
                let isSelected = page == group

                AdjustmentPanel(viewModel: viewModel, group: page, isCompact: isCompact)
                    .offset(x: reduceMotion ? 0 : CGFloat(page.rawValue - group.rawValue) * width)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(isSelected)
                    .accessibilityHidden(!isSelected)
            }
        }
    }

    /// pageStrip names the pages inside a darker capsule, the selected one over a sliding
    /// indicator. The swipe is a high priority gesture: once a finger travels 12 pt it is a
    /// swipe, never also a tap on a name.
    ///
    /// Like a tab bar, the strip stops growing at xLarge, where the five names still fit, and a
    /// long press shows a name in the Large Content Viewer at the accessibility sizes.
    private var pageStrip: some View {
        HStack(spacing: 0) {

            ForEach(AdjustmentGroup.allCases) { page in
                let isSelected = page == group

                Button {
                    group = page
                } label: {
                    Text(page.title)
                        .font(.footnote.weight(isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .foregroundStyle(isSelected ? .primary : .secondary)
                        .padding(.horizontal, isCompact ? 6 : 8)
                        .frame(minHeight: isCompact ? 44 : nil)
                        .padding(.vertical, isCompact ? 0 : 6)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(indicatorFill)
                                    .matchedGeometryEffect(id: "indicator", in: strip)
                            }
                        }
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityShowsLargeContentViewer()
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(stripFill, in: .capsule)
        .padding(.horizontal, 16)
        .padding(.top, isCompact ? 4 : 12)
        .padding(.bottom, isCompact ? 8 : 16)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 12).onEnded { swipe in
                group = group.swiped(by: swipe.translation.width)
            }
        )
    }

    /// stripFill darkens the strip's capsule against the card body: black in the dark scheme,
    /// where a system fill would lighten it, and the tertiary system fill in the light one.
    private var stripFill: Color {
        colorScheme == .dark ? .black.opacity(0.25) : Color(.tertiarySystemFill)
    }

    /// indicatorFill is the selected name's capsule, lighter than the strip, as in a segmented control.
    private var indicatorFill: Color {
        colorScheme == .dark ? .white.opacity(0.2) : .white
    }
}
