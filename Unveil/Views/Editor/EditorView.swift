//
//  EditorView.swift
//  Unveil
//

import SwiftUI

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

    @State
    private var isInfoShown = false

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

            ZStack(alignment: .trailing) {

                EditorCanvas(
                    canvas         : canvas,
                    photo          : session.viewModel.openPhoto,
                    photoSize      : session.viewModel.photoSize,
                    clipping       : session.clippingOverlay,
                    onSingleTap    : { session.select(.move) },
                    onTouchDown    : session.isCardOpen ? { session.select(.move) } : nil,
                    onZoomChange   : { session.zoomPercent = $0 },
                    onWindowChange : { window, isDraft in
                        Task.immediate { await session.viewModel.showWindow(window, draft: isDraft) }
                    }
                )
                .ignoresSafeArea()

                HStack(spacing: 12) {

                    if session.isCardOpen {
                        AdjustCard(
                            viewModel : session.viewModel,
                            group     : $session.selectedGroup,
                            clipping  : $session.clipping
                        )
                        .frame(maxHeight: .infinity, alignment: .top)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }

                    ToolRail(
                        tool        : session.tool,
                        isPhotoOpen : session.viewModel.isPhotoOpen,
                        onSelect    : session.select
                    )
                }
                .padding(16)
                .animation(cardAnimation, value: session.tool)
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
            .toolbar { toolbar }
            .sheet(isPresented: $isInfoShown) {
                PhotoInfoSheet(
                    name : session.viewModel.photoTitle,
                    type : session.viewModel.photoType,
                    size : session.viewModel.photoSize
                )
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

        ToolbarItem(placement: .topBarLeading) {
            Menu {
                Button("Info", systemImage: "info.circle") { isInfoShown = true }
            
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(session.viewModel.photoTitle)
                        .font(.headline)

                    Text(session.viewModel.isEdited ? "Edited" : "Original")
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

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                Task { await session.viewModel.undo() }
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(!session.viewModel.canUndo)

            Button("Redo", systemImage: "arrow.uturn.forward") {
                Task { await session.viewModel.redo() }
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(!session.viewModel.canRedo)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Button("Share", systemImage: "square.and.arrow.up") { }
                .disabled(true)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            Menu("More", systemImage: "ellipsis") {
                Button("Reset All", systemImage: "arrow.counterclockwise") {
                    Task { await session.viewModel.resetAll() }
                }
                .disabled(!session.viewModel.isEdited)

                #if DEBUG
                DiagnosticsMenuItems(diagnostics: diagnostics, isPhotoOpen: session.viewModel.isPhotoOpen)
                #endif
            }
            .accessibilityIdentifier("more-menu")
        }
    }
}
