//
//  EditorView.swift
//  Unveil
//

import SwiftUI
import UIKit

/// EditorView owns the editor layout and system presentations. Its dependencies are composed
/// once per scene; no observable adjustment value or preview frame constructs a new canvas.
struct EditorView<
    Engine       : EngineDriving & EngineDiagnosing,
    Importer     : PhotoImporting,
    LibraryLoader: PhotoLibraryLoading
>: View {

    @Bindable
    private var session: EditorSession<Engine, Importer, LibraryLoader>

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

    @State
    private var isInfoShown = false

    @State
    private var isExportShown = false

    @State
    private var isCropShown = false

    private let canvas     : CanvasView
    private let diagnostics: EditorDiagnostics<Engine, Importer>

    init(
        session    : EditorSession<Engine, Importer, LibraryLoader>,
        canvas     : CanvasView,
        diagnostics: EditorDiagnostics<Engine, Importer>
    ) {
        self.session     = session
        self.canvas      = canvas
        self.diagnostics = diagnostics
    }

    var body: some View {

        NavigationStack {

            GeometryReader { geometry in
                let isBottom = UIDevice.current.userInterfaceIdiom == .phone
                    || horizontalSizeClass == .compact || geometry.size.width < 600
                let layout = isBottom
                    ? AnyLayout(VStackLayout(spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 8))

                layout {
                    EditorCanvas(
                        canvas         : canvas,
                        photo          : session.viewModel.openPhoto,
                        photoSize      : session.viewModel.photoSize,
                        clipping       : session.clippingOverlay,
                        isShowingBefore: session.viewModel.isShowingBefore,
                        onSingleTap    : {},
                        onTouchDown    : nil,
                        onHoldChange   : { session.holdChanged($0) },
                        onToggleBefore : toggleBefore,
                        onZoomChange   : { session.zoomPercent = $0 },
                        onWindowChange : { window, isDraft in
                            Task.immediate { await session.viewModel.showWindow(window, draft: isDraft) }
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                    if session.isCardOpen {
                        AdjustCard(
                            viewModel     : session.viewModel,
                            group         : $session.selectedGroup,
                            clipping      : $session.clipping,
                            width         : isBottom ? max(0, geometry.size.width - 16) : 292,
                            isCompact     : true,
                            histogramHeight: isBottom ? 48 : 68
                        )
                        .frame(height: isBottom ? min(340, geometry.size.height * 0.48) : nil)
                        .frame(maxHeight: isBottom ? nil : .infinity, alignment: .top)
                        .padding(.horizontal, isBottom ? 8 : 0)
                        .padding(.trailing, isBottom ? 0 : 8)
                        .padding(.bottom, 8)
                    }
                }
                .overlay(alignment: .top) {
                    if session.viewModel.isShowingBefore {
                        BeforeCapsule()
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: session.viewModel.isShowingBefore)
                .sensoryFeedback(trigger: session.viewModel.isShowingBefore) { _, isShowing in
                    isShowing ? .impact(weight: .light) : nil
                }
                .overlay(alignment: .bottom) {
                    if let message = session.viewModel.renderErrorMessage {
                        RenderErrorBanner(
                            message   : message,
                            onDismiss : session.viewModel.dismissRenderError
                        )
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .animation(cardAnimation, value: session.viewModel.renderErrorMessage)
                .background(EditorSurround.color.ignoresSafeArea())
                .background { zoomInAliases }
                .background { beforeShortcut }
                .toolbar { toolbar }
            }
            .sheet(isPresented: $isInfoShown) {
                PhotoInfoSheet(
                    name : session.viewModel.photoTitle,
                    type : session.viewModel.photoType,
                    size : session.viewModel.photoSize
                )
            }
            .sheet(isPresented: $isExportShown) {
                PhotoExportSheet(model: session.viewModel)
            }
            .sheet(isPresented: $isCropShown) {
                PhotoCropSheet(model: session.viewModel)
                    .presentationDetents([.large])
            }
            .onChange(of: session.isEditorPresented) { _, shown in
                #if DEBUG
                if shown {
                    isCropShown = ProcessInfo.processInfo.arguments.contains("-UnveilShowCrop")
                    isExportShown = ProcessInfo.processInfo.arguments.contains("-UnveilShowExport")
                }
                #endif
            }

        }
        .preferredColorScheme(.dark)
        .disabled(session.isSavingPhotos)
        .overlay {
            if session.isSavingPhotos {
                ProgressView(session.photosStatus ?? "Saving…")
                    .padding()
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = session.photosStatus, !session.isSavingPhotos {
                Text(message)
                    .font(.caption)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial)
                    .onTapGesture { session.photosStatus = nil }
            }
        }
        .focusedSceneValue(\.zoomCanvas, session.canZoom ? canvas : nil)
        .modifier(EditorAlertPresenter(
            alert     : session.presentedAlert,
            onDismiss : session.dismiss
        ))
    }

    /// zoomInAliases add Cmd = and Cmd Shift = to Zoom In, next to ZoomCommands' Cmd +: plus needs
    /// Shift on a US keyboard and "=" needs it on an Italian one. They are invisible, zero-size
    /// buttons, kept out of the View menu so it lists Zoom In once.
    private var zoomInAliases: some View {
        Group {
            Button("Zoom In", action: canvas.zoomIn)
                .keyboardShortcut("=", modifiers: .command)

            Button("Zoom In", action: canvas.zoomIn)
                .keyboardShortcut("=", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .disabled(!session.canZoom)
    }

    /// beforeShortcut is the backslash key, Lightroom's before and after, as a toggle: the keyboard
    /// reports no key release to SwiftUI, so a hold would need a UIKit key handler. Invisible and
    /// zero-size like zoomInAliases; the More menu has the same toggle for touch.
    private var beforeShortcut: some View {
        Button("Show Original", action: toggleBefore)
            .keyboardShortcut("\\", modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .disabled(!session.canZoom)
    }

    /// setShowingBefore turns the before look on or off for the viewmodel, in order with the edits.
    private func setShowingBefore(_ isShowing: Bool) {
        Task.immediate { await session.viewModel.setShowingBefore(isShowing) }
    }

    private func toggleBefore() {
        setShowingBefore(!session.viewModel.isShowingBefore)
    }

    /// cardAnimation opens and closes the card: a short slide, or a cross-fade under Reduce Motion.
    private var cardAnimation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.25)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {

        ToolbarItem(placement: .topBarLeading) {
            Button(
                "Home",
                systemImage : "chevron.backward",
                action      : session.goHome
            )
            .accessibilityIdentifier("home-button")
        }

        ToolbarSpacer(.fixed, placement: .topBarLeading)

        if horizontalSizeClass != .compact {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button("Info", systemImage: "info.circle") { isInfoShown = true }
            
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.viewModel.photoTitle)
                            .font(.headline)

                        Text((session.viewModel.hdrEnabled ? "HDR · " : "") + (session.viewModel.isEdited ? "Edited" : "Original"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("title-menu")
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .topBarLeading)

            ToolbarItem(placement: .topBarLeading) {
                ZoomPill(session: session, canvas: canvas)
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(session.isCardOpen ? "Done Editing" : "Edit", systemImage: "slider.horizontal.3") {
                session.select(session.isCardOpen ? .move : .adjust)
            }
            .labelStyle(.iconOnly)
            .tint(session.isCardOpen ? .accentColor : .primary)
            .disabled(!session.viewModel.isPhotoOpen)
            .accessibilityValue(session.isCardOpen ? "Editing panel open" : "Editing panel closed")
            .accessibilityIdentifier("adjust-button")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                Task { await session.viewModel.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!session.viewModel.canUndo || session.viewModel.isShowingBefore)

            Button("Redo", systemImage: "arrow.uturn.forward") {
                Task { await session.viewModel.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!session.viewModel.canRedo || session.viewModel.isShowingBefore)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button("Export", systemImage: "square.and.arrow.up") { isExportShown = true }
                .disabled(!session.viewModel.isPhotoOpen)
                .accessibilityIdentifier("export-button")
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu("More", systemImage: "ellipsis") {
                if session.photoContext != nil {
                    Button("Save to Apple Photos", systemImage: "photo.badge.checkmark") {
                        Task { await session.saveToPhotos() }
                    }
                    .disabled(!session.viewModel.isPhotoOpen || session.isSavingPhotos)
                }
                Toggle("HDR Editing", isOn: Binding(
                    get: { session.viewModel.hdrEnabled },
                    set: { value in Task { await session.viewModel.setHDR(value) } }
                ))
                .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore)
                Button("Crop & Rotate", systemImage: "crop.rotate") { isCropShown = true }
                    .disabled(!session.viewModel.isPhotoOpen || session.viewModel.isShowingBefore)
                if horizontalSizeClass == .compact {
                    Text(session.viewModel.photoTitle + (session.viewModel.hdrEnabled ? " · HDR" : ""))
                    Button("Info", systemImage: "info.circle") { isInfoShown = true }
                    Button("Fit Photo", action: canvas.zoomToFit)
                }
                Toggle(
                    "Show Original",
                    systemImage : "circle.lefthalf.filled",
                    isOn        : Binding(
                        get : { session.viewModel.isShowingBefore },
                        set : setShowingBefore
                    )
                )
                .disabled(!session.canZoom)

                Button("Reset All", systemImage: "arrow.counterclockwise") {
                    Task { await session.viewModel.resetAll() }
                }
                .disabled(!session.viewModel.isEdited || session.viewModel.isShowingBefore)

                #if DEBUG
                DiagnosticsMenuItems(diagnostics: diagnostics, isPhotoOpen: session.viewModel.isPhotoOpen)
                #endif
            }
            .accessibilityIdentifier("more-menu")
        }
    }
}
