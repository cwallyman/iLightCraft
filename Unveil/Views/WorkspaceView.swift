//
//  WorkspaceView.swift
//  Unveil
//

import SwiftUI

/// WorkspaceView switches between the home and the editor. Both stay mounted for the scene's
/// lifetime: the editor keeps the single CanvasView (and its zoom) attached, the home keeps the
/// Files and Photos browsers where the user left them. Only visibility, hit testing and
/// accessibility follow the session, with a short scale and fade, a plain cross-fade under
/// Reduce Motion.
struct WorkspaceView<
    Engine       : EngineDriving & EngineDiagnosing,
    Importer     : PhotoImporting,
    LibraryLoader: PhotoLibraryLoading
>: View {

    let session      : EditorSession<Engine, Importer, LibraryLoader>
    let canvas       : CanvasView
    let diagnostics  : EditorDiagnostics<Engine, Importer>
    let launchOptions: MeasurementLaunchOptions

    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {

        let isEditorShown = session.isEditorPresented

        ZStack {

            EditorView(
                session     : session,
                canvas      : canvas,
                diagnostics : diagnostics
            )
            .opacity(isEditorShown ? 1 : 0)
            .scaleEffect(isEditorShown || reduceMotion ? 1 : 1.04)
            .allowsHitTesting(isEditorShown)
            .accessibilityHidden(!isEditorShown)

            HomeView(
                launchOptions : launchOptions,
                isActive      : !isEditorShown,
                isImporting   : session.isImporting,
                onPickFile    : { url in Task { await session.open(pickedURL: url) } },
                onPickPhoto   : { identifier in Task { await session.importLibraryPhoto(assetIdentifier: identifier) } }
            )
            .opacity(isEditorShown ? 0 : 1)
            .scaleEffect(!isEditorShown || reduceMotion ? 1 : 0.96)
            .allowsHitTesting(!isEditorShown)
            .accessibilityHidden(isEditorShown)
        }
        .animation(
            reduceMotion ? .easeInOut(duration: 0.25) : .smooth(duration: 0.35),
            value: isEditorShown
        )
        .confirmationDialog("This photo changed in Apple Photos", isPresented: Binding(
            get: { session.conflictedAssetIdentifier != nil },
            set: { if !$0 { session.conflictedAssetIdentifier = nil } }
        ), titleVisibility: .visible) {
            if let identifier = session.conflictedAssetIdentifier {
                Button("Reload Latest Photos Version") {
                    Task { await session.reloadLatestPhotosVersion(identifier: identifier) }
                }
            }
            Button("Keep Local Edit", role: .cancel) { session.conflictedAssetIdentifier = nil }
        } message: {
            Text("Your local edit is retained. Reload keeps a separate local version and opens the latest Photos item. You can export the local version from Export Photos.")
        }
    }
}
