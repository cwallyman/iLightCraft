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
                    canvas       : canvas,
                    photo        : session.viewModel.openPhoto,
                    photoSize    : session.viewModel.photoSize,
                    onSingleTap  : { session.select(.move) },
                    onZoomChange : { session.zoomPercent = $0 }
                )
                .ignoresSafeArea()

                HStack(spacing: 12) {

                    if session.isCardOpen {
                        AdjustCard(viewModel: session.viewModel, group: $session.selectedGroup)
                            .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                    }

                    ToolRail(
                        tool        : session.tool,
                        isPhotoOpen : session.viewModel.isPhotoOpen,
                        onSelect    : session.select
                    )
                }
                .padding(16)
                .animation(.smooth(duration: 0.3), value: session.tool)
            }
            .toolbar { toolbar }
            .sheet(isPresented: $isInfoShown) {
                PhotoInfoSheet(
                    name : session.viewModel.photoTitle,
                    type : session.viewModel.photoType,
                    size : session.viewModel.photoSize
                )
            }

        }
        .modifier(EditorAlertPresenter(
            alert     : session.presentedAlert,
            onDismiss : session.dismissAlert
        ))
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

        ToolbarSpacer(.fixed, placement: .topBarLeading)

        ToolbarItem(placement: .topBarLeading) {
            ZoomPill(session: session, canvas: canvas)
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button("Undo", systemImage: "arrow.uturn.backward") { }
                .disabled(true)

            Button("Redo", systemImage: "arrow.uturn.forward") { }
                .disabled(true)
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
