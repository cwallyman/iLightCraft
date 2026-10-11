//
//  EditorSession.swift
//  Unveil
//

import Foundation
import Observation
import os

/// EditorSession owns the editor's presentations and the lifetime of a Photos import. Adjustment
/// values stay in EditorViewModel, and frame delivery stays outside observation altogether.
@Observable
@MainActor
final class EditorSession<
    Engine: EngineDriving,
    Importer: PhotoImporting,
    LibraryLoader: PhotoLibraryLoading
> {

    let viewModel: EditorViewModel<Engine, Importer>
    let inspector = AdjustmentInspectorState()

    var isInspectorPresented   : Bool = false
    var isFileImporterPresented: Bool = false
    var isPhotoPickerPresented : Bool = false
    var alert                  : EditorAlert?

    private(set) var isImportingFromLibrary: Bool = false

    private let libraryLoader: LibraryLoader

    @ObservationIgnored
    private var selectedProvider: NSItemProvider?

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

    /// finishPhotoSelection defers loading until the sheet's dismissal completes, so a failed
    /// selection can show its alert on the editor instead of behind the Photos picker.
    func finishPhotoSelection(_ provider: NSItemProvider?) {
        selectedProvider       = provider
        isPhotoPickerPresented = false
    }

    func importSelectedLibraryPhoto() async {
        guard let provider = selectedProvider else { return }

        selectedProvider = nil
        await importLibraryPhoto(from: provider)
    }

    /// importLibraryPhoto holds the staged file through the regular importer, even on a failed
    /// open. Cleanup failures are logged separately and never replace the editing error.
    func importLibraryPhoto(from provider: NSItemProvider) async {
        guard !isImportingFromLibrary else { return }

        isImportingFromLibrary = true
        defer { isImportingFromLibrary = false }

        do throws(PhotoLibraryError) {
            let pickedURL = try await libraryLoader.loadPhoto(from: provider)
            await viewModel.open(pickedURL: pickedURL)

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
}
