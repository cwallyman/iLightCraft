//
//  EditorSession.swift
//  Unveil
//

import Foundation
import Observation
import os

/// EditorSession owns the editor's presentations, home versus editor included, and the lifetime
/// of an import. Adjustment values stay in EditorViewModel, and frame delivery stays outside
/// observation altogether. Only a successful open presents the editor; a failed one leaves the
/// home in place with its alert, and going home keeps the open photo and its values.
@Observable
@MainActor
final class EditorSession<
    Engine: EngineDriving,
    Importer: PhotoImporting,
    LibraryLoader: PhotoLibraryLoading
> {

    let viewModel: EditorViewModel<Engine, Importer>
    let inspector = AdjustmentInspectorState()

    var isInspectorPresented: Bool = false
    var alert               : EditorAlert?

    private(set) var isEditorPresented: Bool = false
    private(set) var isImporting      : Bool = false

    private let libraryLoader: LibraryLoader

    init(
        viewModel    : EditorViewModel<Engine, Importer>,
        libraryLoader: LibraryLoader
    ) {
        self.viewModel     = viewModel
        self.libraryLoader = libraryLoader
    }

    /// presentedAlert gives editing failures priority, retaining diagnostic results until the
    /// user acknowledges the failure. The view model remains the source of editing errors.
    var presentedAlert: EditorAlert? {
        if let message = viewModel.errorMessage {
            return EditorAlert(title: "Photo Error", message: message)
        }

        return alert
    }

    func dismissAlert() {
        if viewModel.errorMessage != nil {
            viewModel.dismissError()
        } else {
            alert = nil
        }
    }

    func showPanel(_ group: AdjustmentGroup) {
        guard viewModel.isPhotoOpen else { return }

        inspector.selectedGroup = group
        isInspectorPresented    = true
    }

    func toggleInspector() {
        if isInspectorPresented {
            isInspectorPresented = false
        } else {
            showPanel(inspector.selectedGroup)
        }
    }

    /// goHome closes the inspector with the editor, so a compact inspector sheet never stays
    /// over the home. The photo, its values and the canvas stay as they are.
    func goHome() {
        isInspectorPresented = false
        isEditorPresented    = false
    }

    /// open imports a file picked in Files (or named by `-UnveilOpen`) and presents the editor
    /// when it worked. A pick while another import runs is ignored.
    func open(pickedURL: URL) async {
        guard !isImporting else { return }

        isImporting = true
        defer { isImporting = false }

        await openAndPresent(pickedURL)
    }

    /// importLibraryPhoto holds the staged file through the regular importer, even on a failed
    /// open. Cleanup failures are logged separately and never replace the editing error.
    func importLibraryPhoto(from provider: NSItemProvider) async {
        guard !isImporting else { return }

        isImporting = true
        defer { isImporting = false }

        do throws(PhotoLibraryError) {
            let pickedURL = try await libraryLoader.loadPhoto(from: provider)
            await openAndPresent(pickedURL)

            do throws(PhotoLibraryError) {
                try await libraryLoader.discardPhoto(at: pickedURL)
            } catch {
                let logger = Logger(subsystem: "com.eliorodr2104.unveil", category: "PhotoLibrary")
                logger.error("Deleting the picker file failed: \(error.message, privacy: .public)")
            }
        } catch {
            alert = EditorAlert(title: "Unable to Open Photo", message: error.message)
        }
    }

    private func openAndPresent(_ pickedURL: URL) async {
        if await viewModel.open(pickedURL: pickedURL) {
            isEditorPresented = true
        }
    }
}
