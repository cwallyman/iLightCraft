//
//  HomePanel.swift
//  Unveil
//

import SwiftUI

/// HomePanel is the glass sheet at the bottom of the home that holds the system Files browser
/// and Photos picker. It snaps between half and full height (below the status bar): dragging
/// its header moves it either way, and a fast upward swipe on the browser content expands it.
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

    @GestureState
    private var dragTranslation: CGFloat = 0

    private static let cornerRadius: CGFloat = 32
    private static let headerHeight: CGFloat = 60

    var body: some View {
        GeometryReader { geometry in

            let fullHeight = geometry.size.height
            let halfHeight = fullHeight / 2
            let baseHeight = isExpanded ? fullHeight : halfHeight
            let height     = min(max(baseHeight - dragTranslation, halfHeight), fullHeight)

            VStack(spacing: 0) {

                header(halfHeight: halfHeight, fullHeight: fullHeight)

                browsers
                    .allowsHitTesting(!isImporting)
                    .overlay {
                        if isImporting {
                            ProgressView("Opening Photo")
                                .padding(20)
                                .glassEffect(.regular, in: .rect(cornerRadius: 20))
                        }
                    }
            }
            .frame(height: height + geometry.safeAreaInsets.bottom, alignment: .top)
            .clipShape(Self.shape)
            .glassEffect(.regular, in: Self.shape)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private static var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: cornerRadius, topTrailingRadius: cornerRadius)
    }

    private func header(
        halfHeight: CGFloat,
        fullHeight: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {

            Capsule()
                .fill(.secondary)
                .frame(width: 40, height: 5)
                .padding(.top, 7)
                .accessibilityHidden(true)

            HStack {

                Picker("Source", selection: $source) {
                    Text("Files")
                        .tag(Source.files)

                    Text("Photos")
                        .tag(Source.photos)
                }
                .pickerStyle(.segmented)
                .fixedSize()

                Spacer()
            }
            .padding(.top, 14)
            .padding(.horizontal, 16)
        }
        .frame(height: Self.headerHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .gesture(dragGesture(halfHeight: halfHeight, fullHeight: fullHeight))
        .accessibilityAction(named: isExpanded ? "Collapse" : "Expand") {
            setExpanded(!isExpanded)
        }
    }

    private var browsers: some View {
        ZStack {

            FilesBrowser(onPick: onPickFile, onSwipeUp: { setExpanded(true) })
                .opacity(source == .files ? 1 : 0)
                .allowsHitTesting(source == .files)
                .accessibilityHidden(source != .files)

            PhotoLibraryPicker(onSelection: onPickPhoto, onSwipeUp: { setExpanded(true) })
                .opacity(source == .photos ? 1 : 0)
                .allowsHitTesting(source == .photos)
                .accessibilityHidden(source != .photos)
        }
    }

    /// dragGesture follows the finger and, on release, snaps to the height nearest to where the
    /// throw would have landed, so a short flick is enough to change state.
    private func dragGesture(
        halfHeight: CGFloat,
        fullHeight: CGFloat
    ) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let baseHeight      = isExpanded ? fullHeight : halfHeight
                let predictedHeight = baseHeight - value.predictedEndTranslation.height

                setExpanded(predictedHeight > (halfHeight + fullHeight) / 2)
            }
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.spring(duration: 0.4, bounce: 0.15)) {
            isExpanded = expanded
        }
    }

    enum Source: Hashable {

        case files
        case photos
    }
}
