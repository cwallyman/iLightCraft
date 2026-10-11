//
//  HomeView.swift
//  Unveil
//

import SwiftUI

/// HomeView is the launch screen: the decorative background with the bottom panel of Files and
/// Photos over it. It owns no session state; picks go to the caller, which presents the editor
/// once the open succeeds.
///
/// It owns the panel's tab and expansion so the background can stop drifting while the expanded
/// panel covers it. Both start from the launch options (`-UnveilHomePhotos`, `-UnveilHomeExpanded`).
struct HomeView: View {

    let isActive   : Bool
    let isImporting: Bool
    let onPickFile : (URL) -> Void
    let onPickPhoto: (NSItemProvider) -> Void

    @State
    private var panelSource: HomePanel.Source

    @State
    private var isPanelExpanded: Bool

    init(
        launchOptions: MeasurementLaunchOptions,
        isActive     : Bool,
        isImporting  : Bool,
        onPickFile   : @escaping (URL) -> Void,
        onPickPhoto  : @escaping (NSItemProvider) -> Void
    ) {
        self.isActive    = isActive
        self.isImporting = isImporting
        self.onPickFile  = onPickFile
        self.onPickPhoto = onPickPhoto

        _panelSource     = State(initialValue: launchOptions.startsHomeOnPhotos ? .photos : .files)
        _isPanelExpanded = State(initialValue: launchOptions.startsHomeExpanded)
    }

    var body: some View {
        ZStack {

            HomeBackground(isMoving: isActive && !isPanelExpanded)

            HomePanel(
                source      : $panelSource,
                isExpanded  : $isPanelExpanded,
                isImporting : isImporting,
                onPickFile  : onPickFile,
                onPickPhoto : onPickPhoto
            )
        }
        .environment(\.colorScheme, .dark)
    }
}
