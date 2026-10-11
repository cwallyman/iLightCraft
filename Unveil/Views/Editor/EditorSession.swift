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

    /// alerts are the diagnostic and import alerts not yet acknowledged, oldest first.
    private(set) var alerts: [EditorAlert] = []

    var selectedGroup : AdjustmentGroup = .light
    var zoomPercent   : Double = 100

    /// clipping is the ends the histogram's corner toggles turned on. It outlives page changes and
    /// closing the card; the canvas shows it only while the toggles are on screen (`clippingOverlay`).
    var clipping: ClippingOverlay = []

    private(set) var tool: EditorTool = .move

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

    var alert: EditorAlert? { alerts.first }

    /// show queues an alert behind the one on screen, unless an identical one already waits.
    func show(_ alert: EditorAlert) {
        if !alerts.contains(alert) {
            alerts.append(alert)
        }
    }

    /// presentedAlert gives editing failures priority, retaining diagnostic results until the
    /// user acknowledges the failure. The view model remains the source of editing errors.
    var presentedAlert: EditorAlert? {
        if let message = viewModel.errorMessage {
            return EditorAlert(title: Self.editingErrorTitle, message: message)
        }

        return alert
    }

    /// dismissAlert acknowledges the alert on screen; the next one queued takes its place.
    func dismissAlert() {
        guard let presentedAlert else { return }

        dismiss(presentedAlert)
    }

    /// dismiss acknowledges `alert`, the one the user saw, wherever it is queued: it may no longer
    /// be the first (a priority error arrived since), and an alert already gone is a no-op.
    func dismiss(_ alert: EditorAlert) {
        if alert.title == Self.editingErrorTitle, viewModel.errorMessage == alert.message {
            viewModel.dismissError()
        } else if let index = alerts.firstIndex(of: alert) {
            alerts.remove(at: index)
        }
    }

    private static var editingErrorTitle: String { "Photo Error" }

    /// isCardOpen is true while the Adjust tool is selected: the adjust card follows it.
    var isCardOpen: Bool { tool == .adjust }

    /// clippingOverlay is what the canvas marks: the ends toggled on, while the card is open.
    var clippingOverlay: ClippingOverlay { isCardOpen ? clipping : [] }

    /// canZoom is true while the editor is on screen with a photo: the scene's zoom commands and
    /// their keyboard shortcuts follow it. The home keeps the photo open, so the photo alone is not enough.
    var canZoom: Bool { isEditorPresented && viewModel.isPhotoOpen }

    /// select changes the tool. Adjust needs an open photo; Move (and closing the card) never does.
    func select(_ tool: EditorTool) {
        guard tool == .move || viewModel.isPhotoOpen else { return }

        self.tool = tool
    }

    func showPanel(_ group: AdjustmentGroup) {
        selectedGroup = group
        select(.adjust)
    }

    /// goHome closes the card with the editor. The photo, its values and the canvas stay as they are.
    func goHome() {
        tool              = .move
        isEditorPresented = false
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
            await openAndPresent(pickedURL, title: Self.title(ofStagedPhoto: pickedURL))

            do throws(PhotoLibraryError) {
                try await libraryLoader.discardPhoto(at: pickedURL)
            } catch {
                let logger = Logger(subsystem: "com.eliorodr2104.unveil", category: "PhotoLibrary")
                logger.error("Deleting the picker file failed: \(error.message, privacy: .public)")
            }
        } catch {
            show(EditorAlert(title: "Unable to Open Photo", message: error.message))
        }
    }

    private func openAndPresent(_ pickedURL: URL, title: String? = nil) async {
        if await viewModel.open(pickedURL: pickedURL, title: title) {
            isEditorPresented = true
        }
    }

    /// title(ofStagedPhoto:) is the picker file's name when it reads like one (IMG_0042), and
    /// "Photo" when it is only a generated identifier.
    private static func title(ofStagedPhoto url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent

        return name.isEmpty || UUID(uuidString: name) != nil ? "Photo" : name
    }
}
