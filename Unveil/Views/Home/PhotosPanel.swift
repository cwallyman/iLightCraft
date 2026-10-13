//
//  PhotosPanel.swift
//  Unveil
//

import SwiftUI

/// PhotosPanel is the glass sheet that holds the library (PhotosBrowser) when the home shows
/// Photos. It stands in for the system Files sheet (DocumentLaunch hides that one) and looks like
/// it: glass that fades into the dark toward the bottom; at rest its top edge is the sheet's
/// (`layout`, window points) and it floats inset from the screen's sides with rounded corners;
/// expanded it reaches the top of the safe area.
///
/// The panel has one size for good, as tall as the expanded panel plus the rubber band, so at rest
/// it runs on past the screen's bottom; it is only ever moved. PanelDragHost moves it in UIKit,
/// with its drag and its snap (HomePanelGeometry), and reports where it settles through
/// `isExpanded`. SwiftUI only places it, at the expanded position, and restricts its touches to
/// where the panel is shown.
///
/// The expansion belongs to HomeView; the source picker rides on the panel's top edge through
/// `fader`, which hides it while the panel is dragged or expanded. While an import
/// runs the browser ignores picks; the session refuses a concurrent import anyway.
struct PhotosPanel: View {

    @Binding
    var isExpanded: Bool

    let library     : PhotoLibraryStore
    let fader       : PickerFader
    let layout      : SheetLayout
    let isImporting : Bool
    let onPickPhoto : (String) -> Void

    /// restingInset is the gap to the screen's sides and bottom at rest, the Files sheet's own.
    private static let restingInset: CGFloat = 8

    /// darkening is the fade over the glass, the Files sheet's look: clear glass behind the
    /// toolbar and the first row, nearly opaque dark gray toward the bottom.
    static let darkening: [Gradient.Stop] = [
        .init(color: .clear, location: 0),
        .init(color: Color(white: 0.11).opacity(0.35), location: 0.3),
        .init(color: Color(white: 0.11).opacity(0.8), location: 0.65),
        .init(color: Color(white: 0.11).opacity(0.92), location: 1)
    ]

    var body: some View {
        GeometryReader { geometry in

            // The host has no safe area of its own: the launch view lays it out full screen.
            let screenTop     = geometry.frame(in: .global).minY
            let expandedTop   = layout.safeTop - screenTop
            let panelGeometry = HomePanelGeometry(travel: max(layout.restingTop - layout.safeTop, 0))
            let contentHeight = max(geometry.size.height - expandedTop, 0)
            let restingOffset = panelGeometry.restingOffset(isExpanded: isExpanded)

            PanelDragHost(
                isExpanded    : $isExpanded,
                library       : library,
                fader         : fader,
                geometry      : panelGeometry,
                contentHeight : contentHeight,
                fadeHeight    : max(contentHeight - panelGeometry.travel - Self.restingInset, 1),
                isImporting   : isImporting,
                onPick        : onPickPhoto
            )
            .frame(
                width  : max(geometry.size.width - Self.restingInset * 2, 0),
                height : contentHeight + HomePanelGeometry.rubberBandLimit
            )
            .contentShape(Rectangle().offset(y: restingOffset))
            .offset(y: expandedTop)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photos Panel")
            .accessibilityIdentifier("PhotosPanel")
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityAction(named: isExpanded ? "Collapse" : "Expand") {
                isExpanded.toggle()
            }
        }
    }
}
