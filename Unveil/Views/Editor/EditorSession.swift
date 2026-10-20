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

    /// toolClosedByTouch is the tool the last touch-down closed, so a hold that follows it can bring
    /// its card back on release; a tap or a pan leaves the card closed. Every touch-down overwrites it.
    @ObservationIgnored
    private var toolClosedByTouch: EditorTool?

    /// holdStartedOnBefore is nil outside a hold and, during one, whether the before look was already
    /// on when it began (backslash or the menu): the release then leaves it on.
    @ObservationIgnored
    private var holdStartedOnBefore: Bool?

    private(set) var isEditorPresented: Bool = false
    private(set) var isImporting      : Bool = false
    private(set) var photoContext: PhotoEditContext?
    private(set) var isSavingPhotos = false
    var conflictedAssetIdentifier: String?
    var photosStatus: String?

    /// onPhotoOpened runs after each successful open, for work that follows one (the import sweep).
    @ObservationIgnored
    var onPhotoOpened: (() -> Void)?

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

    /// touchDown closes the card the moment a finger lands on the canvas and remembers which tool it
    /// closed. A second finger during a hold does not touch the record.
    func touchDown() {
        guard holdStartedOnBefore == nil else { return }

        toolClosedByTouch = isCardOpen ? tool : nil

        if isCardOpen {
            select(.move)
        }
    }

    /// holdChanged shows the before look while the canvas is held. The release returns the look to
    /// what it was before the hold and reopens the card the hold's touch-down closed.
    func holdChanged(_ isHolding: Bool) {
        if isHolding {
            holdStartedOnBefore = viewModel.isShowingBefore
            Task.immediate { await viewModel.setShowingBefore(true) }
            return
        }

        guard let wasShowingBefore = holdStartedOnBefore else { return }

        holdStartedOnBefore = nil

        if !wasShowingBefore {
            Task.immediate { await viewModel.setShowingBefore(false) }
        }

        if let tool = toolClosedByTouch {
            toolClosedByTouch = nil
            select(tool)
        }
    }

    func showPanel(_ group: AdjustmentGroup) {
        selectedGroup = group
        select(.adjust)
    }

    /// goHome closes the card with the editor. The photo, its values and the canvas stay as they are.
    func goHome() {
        tool                = .move
        isEditorPresented   = false
        toolClosedByTouch   = nil
        holdStartedOnBefore = nil

        Task.immediate { await viewModel.setShowingBefore(false) }
    }

    /// open imports a file picked in Files (or named by `-UnveilOpen`) and presents the editor
    /// when it worked. A pick while another import runs is ignored.
    func open(pickedURL: URL) async {
        guard !isImporting else { return }

        isImporting = true
        defer { isImporting = false }

        if await openAndPresent(pickedURL) { photoContext = nil }
    }

    /// importLibraryPhoto copies a library photo to a staging file and holds it through the
    /// regular importer, even on a failed open. Cleanup failures are logged separately and never
    /// replace the editing error.
    func importLibraryPhoto(assetIdentifier: String) async {
        guard !isImporting else { return }

        isImporting = true
        defer { isImporting = false }

        do throws(PhotoLibraryError) {
            let pickedURL = try await libraryLoader.loadPhoto(assetIdentifier: assetIdentifier)
            let context: PhotoEditContext?
            do { context = try PhotoEditContext.read(for: pickedURL) }
            catch { throw .fileOperationFailed(error.localizedDescription) }
            let title = context?.displayName.map { URL(filePath: $0).deletingPathExtension().lastPathComponent }
                ?? Self.title(ofStagedPhoto: pickedURL)
            if await openAndPresent(pickedURL, title: title, initialSettings: context?.initialSettings,
                                    versionKey: context.map { $0.assetIdentifier + "/" + $0.sourceFile }) {
                photoContext = context
                if let copy = viewModel.openCopyURL {
                    do { photoContext?.rawDecoderVersion = try NativeImageInfo.read(for: copy)?.rawDecoderVersion ?? context?.rawDecoderVersion }
                    catch { throw .fileOperationFailed(error.localizedDescription) }
                }
            }

            do throws(PhotoLibraryError) {
                try await libraryLoader.discardPhoto(at: pickedURL)
            } catch {
                let logger = Logger(subsystem: "com.eliorodr2104.unveil", category: "PhotoLibrary")
                logger.error("Deleting the library copy failed: \(error.message, privacy: .public)")
            }
        } catch {
            if error == .externalChange {
                conflictedAssetIdentifier = assetIdentifier
            } else {
                show(EditorAlert(title: "Unable to Open Photo", message: error.message))
            }
        }
    }

    @discardableResult
    private func openAndPresent(_ pickedURL: URL, title: String? = nil, initialSettings: Data? = nil, versionKey: String? = nil) async -> Bool {
        if await viewModel.open(pickedURL: pickedURL, title: title, initialSettings: initialSettings, versionKey: versionKey) {
            isEditorPresented = true
            onPhotoOpened?()
            return true
        }
        return false
    }

    /// title(ofStagedPhoto:) is the library file's name when it reads like one (IMG_0042), and
    /// "Photo" when it is only a generated identifier.
    private static func title(ofStagedPhoto url: URL) -> String {
        let name = url.deletingPathExtension().lastPathComponent

        return name.isEmpty || UUID(uuidString: name) != nil ? "Photo" : name
    }
}

extension EditorSession where Engine: EngineDiagnosing {

    func saveToPhotos() async {
        guard !isSavingPhotos, let context = photoContext, let photo = viewModel.openPhoto else { return }
        isSavingPhotos = true
        photosStatus = "Rendering full-resolution photo…"
        defer { isSavingPhotos = false }
        let hdr = viewModel.hdrEnabled
        let file = URL.temporaryDirectory.appending(path: "photos-save-\(UUID())").appendingPathExtension(hdr ? "tiff" : "jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        do {
            await viewModel.finishPendingEdits()
            let settings = try await viewModel.photoCommand("develop.get", params: [String: String]())
            if hdr {
                _ = try await viewModel.photoCommand("unveil.hdrExport", params: ["path": file.path(percentEncoded: false)])
            } else {
                _ = try await viewModel.photoCommand("unveil.export", params: PhotosExportRequest(
                    id: photo.rawValue, path: file.path(percentEncoded: false)
                ))
            }
            let result = try await ApplePhotosEditor.save(context: context, rendered: file, settings: Data(settings.utf8), hdr: hdr)
            photoContext = result.0
            photosStatus = result.1 ?? "Saved to the same Apple Photos item. Original preserved."
        } catch PhotoLibraryError.externalChange {
            conflictedAssetIdentifier = context.assetIdentifier
            photosStatus = "Photos changed; local edit retained."
        } catch {
            photosStatus = "Save stopped; local edit retained."
            show(EditorAlert(title: "Unable to Save to Photos", message: (error as? EngineError)?.message
                             ?? (error as? PhotoLibraryError)?.message ?? error.localizedDescription))
        }
    }

    func reloadLatestPhotosVersion(identifier: String? = nil) async {
        guard let identifier = identifier ?? conflictedAssetIdentifier else { return }
        do {
            try ApplePhotosEditor.archiveWorkingVersion(identifier: identifier)
            conflictedAssetIdentifier = nil
            await importLibraryPhoto(assetIdentifier: identifier)
        } catch {
            show(EditorAlert(title: "Unable to Reload Photo", message: error.localizedDescription))
        }
    }
}
