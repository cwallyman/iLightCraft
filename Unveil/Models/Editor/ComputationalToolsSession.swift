//
//  ComputationalToolsSession.swift
//  Unveil
//

import Foundation
import Observation
import UIKit

/// ComputationalToolsSession serializes local analysis and saves real masks/removal settings in the engine.
@Observable
@MainActor
final class ComputationalToolsSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    private(set) var image: UIImage?
    private(set) var busy = false
    private(set) var status = ""
    var error: String?
    var exposure = 0.0
    var brushSize = 0.025
    var selectedMask: UInt32?
    var maskOperation = "new"
    var refinement = 0.0
    var showMaskOverlay = true
    var isPickingObject = false
    private var overlayMaskID: UInt32?
    private var closeRequested = false
    private(set) var maskOverlay: UIImage?
    private(set) var masks: [SavedMask] = []
    var description: OnDeviceAnalysis.Description?
    var stroke: [CGPoint] = []
    var query = "" { didSet { refreshSearch() } }
    private(set) var results: [LocalAnalysisIndex.Entry] = []
    private var searchTask: Task<Void, Never>?
    private(set) var index = LocalAnalysisIndex()
    private(set) var catalog: [PhotoMergeSession<Engine, Importer>.Photo] = []
    private var folder: URL?
    private(set) var preview: URL?
    private var task: Task<Void, Never>?
    private let onIndexed: @MainActor (PhotoID, URL) async -> Void
    nonisolated struct SavedMask: Decodable, Identifiable {
        let id: UInt32; let name: String; let adjust: Adjust; let refine: Double?
        struct Adjust: Decodable { let exposure: Double }
    }
    nonisolated struct MaskList: Decodable { let masks: [SavedMask] }
    nonisolated struct MaskRefine: Encodable, Sendable { let id: UInt32; let value: Double }
    nonisolated struct CatalogSource: Decodable {
        let source: Source
        struct Source: Decodable { let type: String; let path: String? }
    }

    nonisolated struct PreviewRequest: Encodable, Sendable { let path: String }
    nonisolated struct SelectionRequest: Encodable, Sendable {
        let side: Int
        let alpha: [UInt8]
        let name: String
        let maskID: UInt32?
        let op: String
    }
    nonisolated struct MaskResult: Decodable { let activeMask: UInt32 }
    nonisolated struct MaskAdjustment: Encodable, Sendable {
        let id: UInt32
        let values: Values
        struct Values: Encodable, Sendable { let exposure: Double }
    }
    nonisolated struct Spot: Encodable, Sendable {
        let mode = "remove"
        let points: [[Double]]
        let size: Double
        let feather = 60
        let opacity = 100
    }
    init(model: EditorViewModel<Engine, Importer>, onIndexed: @escaping @MainActor (PhotoID, URL) async -> Void) { self.model = model; self.onIndexed = onIndexed }

    func load() async {
        guard folder == nil else { return }
        do {
            let folder = URL.temporaryDirectory.appending(path: "iLightCraftAnalysis-\(UUID())")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.folder = folder
            try await refreshImage()
            try await refreshMasks()
            index = try await Task.detached { try LocalAnalysisIndex.load() }.value
            refreshSearch()
        } catch { self.error = error.localizedDescription }
    }
    func close() {
        closeRequested = true
        task?.cancel(); searchTask?.cancel()
        if !busy { removePreviewFiles() }
    }
    private func removePreviewFiles() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
        self.folder = nil
    }
    func cancel() { task?.cancel() }

    func select(people: Bool, background: Bool, point: CGPoint? = nil) {
        isPickingObject = false
        run("Selecting on device…") {
            guard let preview = self.preview else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
            let selection = try await Task.detached(priority: .userInitiated) {
                try OnDeviceAnalysis.selection(at: preview, people: people, background: background, point: point)
            }.value
            try Task.checkCancellation()
            let name = point != nil ? "Object" : (people ? "People" : (background ? "Background" : "Subject"))
            let text = try await self.model.performPhotoEdit("unveil.maskFromAlpha", params: SelectionRequest(
                side: selection.side, alpha: selection.alpha, name: name, maskID: self.maskOperation == "new" ? nil : self.selectedMask, op: self.maskOperation
            ))
            self.selectedMask = try JSONDecoder().decode(MaskResult.self, from: Data(text.utf8)).activeMask
            self.exposure = 0
            if self.maskOperation == "new" { self.overlayMaskID = self.selectedMask; self.maskOverlay = Self.overlay(selection) }
            else { self.maskOverlay = nil }
            try await self.refreshMasks()
            self.status = "\(name) mask created. Adjust its exposure below."
        }
    }
    func applyExposure() {
        guard let id = selectedMask else { return }
        run("Applying mask adjustment…") {
            _ = try await self.model.performPhotoEdit("mask.adjust", params: MaskAdjustment(id: id, values: .init(exposure: self.exposure)))
            try await self.refreshImage()
            try await self.refreshMasks()
            self.status = "Mask adjustment saved. Undo and Photos settings include the mask."
        }
    }
    func restoreMaskControls() {
        guard let mask = masks.first(where: { $0.id == selectedMask }) else { return }
        exposure = mask.adjust.exposure; refinement = mask.refine ?? 0
        if selectedMask != overlayMaskID { maskOverlay = nil }
    }
    func refineMask() {
        guard let id = selectedMask else { return }
        run("Refining mask edges…") {
            _ = try await self.model.performPhotoEdit("mask.refine", params: MaskRefine(id: id, value: self.refinement))
            try await self.refreshMasks(); try await self.refreshImage()
            self.maskOverlay = nil; self.status = "Edge refinement saved."
        }
    }
    func invertMask() {
        guard let id = selectedMask else { return }
        run("Inverting mask…") {
            _ = try await self.model.performPhotoEdit("mask.invert", params: ["id": id])
            self.maskOverlay = nil; try await self.refreshImage()
        }
    }
    func deleteMask() {
        guard let id = selectedMask else { return }
        run("Deleting mask…") {
            _ = try await self.model.performPhotoEdit("mask.delete", params: ["id": id])
            self.selectedMask = nil; self.maskOverlay = nil; self.maskOperation = "new"
            try await self.refreshMasks(); try await self.refreshImage()
        }
    }
    private func refreshMasks() async throws {
        let text = try await model.photoCommand("develop.get", params: [String: String]())
        masks = try JSONDecoder().decode(MaskList.self, from: Data(text.utf8)).masks
        restoreMaskControls()
        if masks.isEmpty { maskOperation = "new" }
    }
    private static func overlay(_ selection: OnDeviceAnalysis.Selection) -> UIImage? {
        var bytes = [UInt8](repeating: 0, count: selection.alpha.count * 4)
        for (index, alpha) in selection.alpha.enumerated() {
            bytes[index * 4] = 242; bytes[index * 4 + 1] = 165; bytes[index * 4 + 2] = 22; bytes[index * 4 + 3] = alpha
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: selection.side, height: selection.side, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: selection.side * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }
    func openIndexed(_ entry: LocalAnalysisIndex.Entry) {
        run("Opening local draft…") {
            let text = try await self.model.photoCommand("photo.inspect", params: ["id": entry.id])
            let photo = try JSONDecoder().decode(CatalogSource.self, from: Data(text.utf8))
            guard photo.source.type == "file", let path = photo.source.path else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
            await self.onIndexed(PhotoID(rawValue: entry.id), URL(filePath: path))
        }
    }

    func removeStroke() {
        guard !stroke.isEmpty else { return }
        let points = stroke.map { [Double(min(1, max(0, $0.x))), Double(min(1, max(0, $0.y)))] }
        guard points.count <= 2048 else { error = "Use a shorter removal stroke."; return }
        let size = brushSize
        run("Removing selected area…") {
            _ = try await self.model.performPhotoEdit("spot.add", params: Spot(points: points, size: size))
            self.stroke = []
            try await self.refreshImage()
            self.status = "Content-aware heal applied. Generative filling is not enabled."
        }
    }
    func analyze() {
        run("Analyzing on device…") {
            guard let preview = self.preview else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
            let result = try await Task.detached(priority: .userInitiated) { try OnDeviceAnalysis.describe(at: preview) }.value
            try Task.checkCancellation()
            self.description = result
            if let photo = self.model.openPhoto {
                var index = self.index
                try index.record(id: photo.rawValue, name: self.model.photoTitle, analysis: result)
                let snapshot = index
                try await Task.detached { try snapshot.save() }.value
                self.index = index
                self.refreshSearch()
            }
            self.status = "Local labels, text and face count. No identity recognition is implied."
        }
    }
    func clearIndex() {
        run("Clearing the private analysis index…") {
            let empty = LocalAnalysisIndex()
            try await Task.detached { try empty.save() }.value
            self.index = empty; self.description = nil; self.refreshSearch()
            self.status = "Private analysis index cleared. Photo files and edits are unchanged."
        }
    }
    private func refreshSearch() {
        searchTask?.cancel()
        let index = index, query = query
        searchTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(180))
                let matches = await Task.detached(priority: .userInitiated) { index.search(query) }.value
                try Task.checkCancellation()
                self.results = matches
            } catch { return }
        }
    }

    func indexImportedPhotos() {
        run("Reading imported library…") {
            var photos: [PhotoMergeSession<Engine, Importer>.Photo] = []
            var total = 1
            while photos.count < total && photos.count < 1000 {
                let text = try await self.model.photoCommand("catalog.query", params: ["offset": photos.count, "limit": 50])
                let page = try JSONDecoder().decode(PhotoMergeSession<Engine, Importer>.Page.self, from: Data(text.utf8))
                total = min(1000, page.total)
                guard !page.photos.isEmpty else { break }
                photos += await PhotoMergeSession<Engine, Importer>.Photo.resolvingNames(page.photos)
            }
            self.catalog = photos
            var index = self.index
            for (position, photo) in photos.enumerated() {
                try Task.checkCancellation()
                self.status = "Analyzing imported photo \(position + 1) of \(photos.count)…"
                guard let folder = self.folder else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
                let path = folder.appending(path: "index-\(photo.id).png")
                defer { try? FileManager.default.removeItem(at: path) }
                let params = IndexPreview(path: path.path, id: photo.id)
                _ = try await self.model.photoCommand("unveil.cropPreview", params: params)
                let work = Task.detached(priority: .utility) { try OnDeviceAnalysis.describe(at: path) }
                let description = try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                try index.record(id: photo.id, name: photo.name, analysis: description)
                let snapshot = index
                try await Task.detached { try snapshot.save() }.value
                self.index = index
                self.refreshSearch()
            }
            self.status = "Imported library indexed locally. Searches match saved labels/text; semantic matching uses local English label/text embeddings when available."
        }
    }
    nonisolated struct IndexPreview: Encodable, Sendable { let path: String; let id: UInt64 }

    private func refreshImage() async throws {
        guard let folder else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
        let url = folder.appending(path: "preview-\(UUID()).png")
        _ = try await model.photoCommand("unveil.cropPreview", params: PreviewRequest(path: url.path))
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        guard let image = UIImage(data: data) else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
        if let old = preview { try? FileManager.default.removeItem(at: old) }
        preview = url
        self.image = image
    }
    private func run(_ message: String, operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        error = nil
        status = message
        task = Task {
            defer { self.busy = false; if self.closeRequested { self.removePreviewFiles() } }
            do { try await operation() }
            catch is CancellationError { self.status = "Cancelled before applying the next change." }
            catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
        }
    }
}
