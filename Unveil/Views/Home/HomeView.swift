//
//  HomeView.swift
//  Unveil
//

import SwiftUI

/// HomeView is the launch screen: the system document launch view (DocumentLaunch) with our
/// backdrop, the system Files sheet, and a floating source picker just above the sheet's top
/// edge. Choosing Photos hides the Files sheet and shows PhotosPanel, our own library browser,
/// in its place. It owns no session state; picks go to the caller, which presents the editor once
/// the open succeeds. It asks for photo library access when the Photos source is selected.
///
/// The picker fades out the moment either panel is dragged and stays out while it is expanded
/// (PickerFader), so it never sits over a moving panel's edge. HomeView tracks both expansions so
/// the background stops drifting while it is hidden. Both browsers stay alive across switches, so
/// each keeps its place. The tab and the expansion start from the launch options
/// (`-UnveilHomePhotos`, `-UnveilHomeExpanded`).
struct HomeView: View {

    let isActive      : Bool
    let isImporting   : Bool
    let onPickFile    : (URL) -> Void
    let onPickPhoto   : (String) -> Void
    let startsExpanded: Bool

    @State
    private var library = PhotoLibraryStore()

    /// fader hides the source picker while the panel shown is dragged or expanded.
    @State
    private var fader = PickerFader()

    @State
    private var source: Source

    @State
    private var isFilesExpanded = false

    @State
    private var isPhotosExpanded: Bool

    /// sheetLayout is where the Files sheet rests, nil until it first lays out. The source
    /// picker and the Photos panel wait for it.
    @State
    private var sheetLayout: SheetLayout?

    init(
        launchOptions: MeasurementLaunchOptions,
        isActive     : Bool,
        isImporting  : Bool,
        onPickFile   : @escaping (URL) -> Void,
        onPickPhoto  : @escaping (String) -> Void
    ) {
        self.isActive       = isActive
        self.isImporting    = isImporting
        self.onPickFile     = onPickFile
        self.onPickPhoto    = onPickPhoto
        self.startsExpanded = launchOptions.startsHomeExpanded && !launchOptions.startsHomeOnPhotos

        _source = State(initialValue: launchOptions.startsHomeOnPhotos
                        || UserDefaults.standard.string(forKey: "UnveilPreferredLibrary") == "photos" ? .photos : .files)
        _isPhotosExpanded = State(initialValue: launchOptions.startsHomeExpanded && launchOptions.startsHomeOnPhotos)
    }

    var body: some View {

        let isCovered = source == .files ? isFilesExpanded : isPhotosExpanded

        DocumentLaunch(
            showsFiles     : source == .files,
            switchDrift    : Self.switchDrift,
            isInteractive  : !isImporting,
            startsExpanded : startsExpanded,
            onPickFile     : onPickFile,
            onLayout       : { layout in sheetLayout = layout },
            onExpanded     : { expanded in
                isFilesExpanded = expanded
                fader.setExpanded(expanded, for: .files)
            },
            onDragging     : { isDragging in fader.setDragging(isDragging, for: .files) },
            background     : HomeBackground(isMoving: isActive && !isCovered, panelTop: sheetLayout?.restingTop),
            foreground     : foreground
        )
        .ignoresSafeArea()
        .overlay {
            if isImporting {
                ProgressView("Opening Photo")
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 20))
            }
        }
        .environment(\.colorScheme, .dark)
        .task(id: source) {
            UserDefaults.standard.set(source == .photos ? "photos" : "files", forKey: "UnveilPreferredLibrary")
            if source == .photos { await library.requestAccess() }
        }
    }

    /// foreground is what the launch view puts in front of the title and behind the Files sheet:
    /// the source picker, and the Photos panel over it.
    @ViewBuilder
    private var foreground: some View {
        if let sheetLayout {
            ZStack {

                GeometryReader { geometry in
                    SourcePickerHost(source: $source, fader: fader)
                        .padding(.leading, 20)
                        .frame(
                            maxWidth  : .infinity,
                            maxHeight : max(sheetLayout.restingTop - geometry.frame(in: .global).minY - 12, 0),
                            alignment : .bottomLeading
                        )
                }
                .accessibilityHidden(source == .photos ? isPhotosExpanded : isFilesExpanded)

                PhotosPanel(
                    isExpanded   : $isPhotosExpanded,
                    library      : library,
                    fader        : fader,
                    layout       : sheetLayout,
                    isImporting  : isImporting,
                    onPickPhoto  : onPickPhoto
                )
                .opacity(source == .photos ? 1 : 0)
                .offset(y: source == .photos ? 0 : Self.switchDrift)
                .allowsHitTesting(source == .photos)
                .accessibilityHidden(source != .photos)
            }
            .environment(\.colorScheme, .dark)
        }
    }

    /// switchDrift is how far the outgoing panel sinks, and the incoming one rises, while Files
    /// and Photos cross-fade: enough to read as motion, short of a slide.
    private static let switchDrift: CGFloat = 14

    enum Source: Hashable {

        case files
        case photos
    }
}
