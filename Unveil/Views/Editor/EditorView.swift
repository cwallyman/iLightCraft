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

    @Environment(\.horizontalSizeClass)
    private var horizontalSizeClass

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
            
            EditorCanvas(canvas: canvas, photo: session.viewModel.openPhoto) {
                session.isInspectorPresented = false
            }
            .ignoresSafeArea()
            .toolbar { toolbar }
            .inspector(isPresented: $session.isInspectorPresented) {
                inspector
            }
            
        }
        .modifier(EditorAlertPresenter(
            alert     : session.presentedAlert,
            isActive  : !isCompactInspectorPresented,
            onDismiss : session.dismissAlert
        ))
    }

    private var isCompactInspectorPresented: Bool {
        horizontalSizeClass == .compact && session.isInspectorPresented
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

        ToolbarItemGroup(placement: .topBarTrailing) {
            DiagnosticsMenu(diagnostics: diagnostics, isPhotoOpen: session.viewModel.isPhotoOpen)

            Button(
                "Adjustments",
                systemImage : "slider.horizontal.3",
                action      : session.toggleInspector
            )
            .disabled(!session.viewModel.isPhotoOpen)
            .accessibilityIdentifier("adjustments-toggle")
        }
    }

    private var inspector: some View {
        
        NavigationStack {
        
            AdjustmentInspector(
                viewModel: session.viewModel,
                selection: session.inspector
            )
            .navigationTitle("Adjustments")
            .navigationBarTitleDisplayMode(.inline)

        }
        .inspectorColumnWidth(360)
        .modifier(
            EditorAlertPresenter(
                alert    : session.presentedAlert,
                isActive : isCompactInspectorPresented,
                onDismiss: session.dismissAlert
            )
        )
    }
}
