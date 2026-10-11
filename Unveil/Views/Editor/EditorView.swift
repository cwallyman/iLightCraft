//
//  EditorView.swift
//  Unveil
//

import SwiftUI
import UniformTypeIdentifiers

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
            .overlay {
                if !session.viewModel.isPhotoOpen {
                    emptyState
                }
            }
            .toolbar { toolbar }
            .inspector(isPresented: $session.isInspectorPresented) {
                inspector
            }
            
        }
        .fileImporter(
            isPresented         : $session.isFileImporterPresented,
            allowedContentTypes : [.rawImage, .image]
        ) { result in
            switch result {
                case .success(let url):
                    Task { await session.viewModel.open(pickedURL: url) }

                case .failure(let error):
                    session.alert = EditorAlert(
                        title   : "Unable to Open Photo",
                        message : error.localizedDescription
                    )
            }
        }
        .sheet(
            isPresented : $session.isPhotoPickerPresented,
            onDismiss   : { Task { await session.importSelectedLibraryPhoto() } }
        ) {
            PhotoLibraryPicker(onSelection: session.finishPhotoSelection)
                .ignoresSafeArea()
        }
        .modifier(EditorAlertPresenter(
            alert     : session.presentedAlert,
            isActive  : !isCompactInspectorPresented
                && !session.isPhotoPickerPresented && !session.isFileImporterPresented,
            onDismiss : session.dismissAlert
        ))
    }

    private var isCompactInspectorPresented: Bool {
        horizontalSizeClass == .compact && session.isInspectorPresented
    }

    private var emptyState: some View {
        OpenPhotoButton(
            openPhotos : { session.isPhotoPickerPresented = true },
            openFiles  : { session.isFileImporterPresented = true }
        )
        .frame(maxWidth: 520, maxHeight: 380)
        .padding(48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .disabled(session.isImportingFromLibrary)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                PhotoImportActions(
                    openPhotos : { session.isPhotoPickerPresented = true },
                    openFiles  : { session.isFileImporterPresented = true }
                )
                
            } label: {
                Image(systemName: "folder")
            }
            .disabled(session.isImportingFromLibrary)
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
