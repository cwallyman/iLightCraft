//
//  HomePanel.swift
//  Unveil
//

import SwiftUI
import UIKit

/// HomePanel is the glass sheet at the bottom of the home that holds the system Files browser
/// and Photos picker. It rests at half or full height (below the status bar). At half height a
/// header holds the source picker and the grabber; at full height the header goes away, the
/// browser takes the whole panel, and a floating capsule holds the picker and a Collapse button.
///
/// It is always laid out at full height and only moved by an offset (HomePanelGeometry), so a
/// drag never re-lays out the two embedded browsers. Dragging the header moves it 1:1 either way,
/// rubber-banded past the ends, and a release snaps with a spring that starts at the finger's
/// speed. The browsers' frame never changes either: the header floats over them in an overlay,
/// and while collapsed the browsers are shifted below it by an offset, so expanding slides them
/// up as the header fades out, with no layout pass in the out-of-process browsers.
///
/// While collapsed, PanelDragSurface covers the browsers: the browsers run out of process and
/// their touches never reach the host, so the cover takes the first drag (which moves the panel
/// like the header) and a tap (which expands it). The cover switches off the moment the panel
/// is told to expand, before the snap runs, and from then on the browser gets every touch.
///
/// Both browsers stay alive and the inactive one is only hidden, so each keeps its own folder,
/// scroll position and search while the user switches tabs. While an import runs the panel
/// shows progress and ignores picks; the session refuses a concurrent import anyway. The tab
/// and the expansion belong to HomeView, which also stops the background while expanded.
struct HomePanel: View {

    @Binding
    var source: Source

    @Binding
    var isExpanded: Bool

    let isImporting: Bool
    let onPickFile : (URL) -> Void
    let onPickPhoto: (NSItemProvider) -> Void

    @State
    private var dragTranslation: CGFloat = 0

    private static let cornerRadius: CGFloat = 32
    private static let headerHeight: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in

            let panelGeometry = HomePanelGeometry(travel: geometry.size.height / 2)
            let offset        = panelGeometry.offset(isExpanded: isExpanded, translation: dragTranslation)

            // Pinned to the top of the safe area and moved down by the offset; the glass runs on
            // past the screen's bottom so a rubber band past full height never shows a gap.
            browsers(panelGeometry)
                .offset(y: isExpanded ? 0 : Self.headerHeight)
                .frame(height: geometry.size.height + geometry.safeAreaInsets.bottom, alignment: .top)
                .overlay(alignment: .top) {
                    if !isExpanded {
                        header(panelGeometry)
                            .transition(.opacity.combined(with: .offset(y: -Self.headerHeight)))
                    }
                }
                .overlay(alignment: .bottom) {
                    if isExpanded {
                        expandedControls(panelGeometry)
                            .padding(.bottom, geometry.safeAreaInsets.bottom + 16)
                            .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                    }
                }
                .padding(.bottom, HomePanelGeometry.rubberBandLimit)
                .clipShape(Self.shape)
                .glassEffect(.regular, in: Self.shape)
                .offset(y: offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
    }

    private func header(_ panelGeometry: HomePanelGeometry) -> some View {
        ZStack(alignment: .top) {

            Capsule()
                .fill(.secondary)
                .frame(width: 40, height: 5)
                .padding(.top, 7)
                .accessibilityHidden(true)

            HStack {

                sourcePicker

                Spacer()
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
        }
        .frame(height: Self.headerHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(
            PanelPanGesture(
                onChanged : { translation in dragTranslation = translation },
                onEnded   : { translation, velocity in
                    settle(translation: translation, velocity: velocity, in: panelGeometry)
                }
            )
        )
        .accessibilityAction(named: "Expand") {
            settle(expanded: true, from: dragTranslation, velocity: 0, in: panelGeometry)
        }
    }

    /// expandedControls replace the header at full height: a small floating glass capsule at the
    /// bottom center with the source picker and a button that collapses the panel.
    private func expandedControls(_ panelGeometry: HomePanelGeometry) -> some View {
        HStack(spacing: 4) {

            sourcePicker

            Button {
                settle(expanded: false, from: dragTranslation, velocity: 0, in: panelGeometry)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 32)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Collapse")
        }
        .padding(6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $source) {
            Text("Files")
                .tag(Source.files)

            Text("Photos")
                .tag(Source.photos)
        }
        .pickerStyle(.segmented)
        .fixedSize()
    }

    private func browsers(_ panelGeometry: HomePanelGeometry) -> some View {
        ZStack {

            FilesBrowser(onPick: onPickFile, isInteractive: isBrowsing(.files))
                .opacity(source == .files ? 1 : 0)
                .allowsHitTesting(isBrowsing(.files))
                .accessibilityHidden(!isExpanded || source != .files)

            PhotoLibraryPicker(onSelection: onPickPhoto, isInteractive: isBrowsing(.photos))
                .opacity(source == .photos ? 1 : 0)
                .allowsHitTesting(isBrowsing(.photos))
                .accessibilityHidden(!isExpanded || source != .photos)
        }
        .overlay {
            // Always in the tree and switched by isActive, not inserted and removed: a removed
            // view can linger through the snap's transaction, while isActive applies at once.
            PanelDragSurface(
                isActive      : !isExpanded,
                onDragChanged : { translation in dragTranslation = translation },
                onDragEnded   : { translation, velocity in
                    settle(translation: translation, velocity: velocity, in: panelGeometry)
                },
                onExpand      : {
                    settle(expanded: true, from: dragTranslation, velocity: 0, in: panelGeometry)
                }
            )
            .allowsHitTesting(!isExpanded)
        }
        .overlay {
            if isImporting {
                ProgressView("Opening Photo")
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
    }

    /// isBrowsing tells whether a browser may take touches: only the visible one, only once the
    /// panel is expanded and never during an import. Its out-of-process view is told directly.
    private func isBrowsing(_ browserSource: Source) -> Bool {
        isExpanded && source == browserSource && !isImporting
    }

    /// settle ends a drag: the release picks the detent, and the snap starts where the finger let go.
    private func settle(
        translation: CGFloat,
        velocity   : CGFloat,
        in geometry: HomePanelGeometry
    ) {
        let expands = geometry.settlesExpanded(
            isExpanded  : isExpanded,
            translation : translation,
            velocity    : velocity
        )

        settle(
            expanded : expands,
            from     : translation,
            velocity : velocity,
            in       : geometry
        )
    }

    /// settle moves the panel from wherever it is shown now to a detent, with a critically damped
    /// spring whose start matches the release velocity (points per second, positive downward).
    private func settle(
        expanded        : Bool,
        from translation: CGFloat,
        velocity        : CGFloat,
        in geometry     : HomePanelGeometry
    ) {
        let released = geometry.offset(isExpanded: isExpanded, translation: translation)
        let target   = geometry.restingOffset(isExpanded: expanded)
        let start    = geometry.snapVelocity(from: released, to: target, velocity: velocity)

        let spring = Animation.interpolatingSpring(
            duration        : HomePanelGeometry.snapDuration,
            bounce          : 0,
            initialVelocity : start
        )

        withAnimation(spring) {
            isExpanded      = expanded
            dragTranslation = 0
        }
    }

    enum Source: Hashable {

        case files
        case photos
    }
}

/// PanelPanGesture is the header's drag as a UIKit pan, so it behaves like PanelDragSurface's:
/// translation and velocity in window coordinates (the header moves under the finger), and a
/// cancelled pan still settles the panel on a detent.
private struct PanelPanGesture: UIGestureRecognizerRepresentable {

    let onChanged: (CGFloat) -> Void
    let onEnded  : (CGFloat, CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        UIPanGestureRecognizer()
    }

    func handleUIGestureRecognizerAction(
        _ pan  : UIPanGestureRecognizer,
        context: Context
    ) {
        switch pan.state {
            case .began, .changed:
                onChanged(pan.translation(in: nil).y)

            case .ended, .cancelled:
                onEnded(pan.translation(in: nil).y, pan.velocity(in: nil).y)

            default:
                break
        }
    }
}
