//
//  ComputationalToolsSession.swift
//  iLightCraft
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
    var maskColor = MaskColorAdjustments()
    var exposure: Double {
        get { maskColor.exposure }
        set { maskColor.exposure = newValue }
    }
    var brushSize = 0.025
    var removalMode = "remove"
    var removalFeather = 60.0
    var removalOpacity = 100.0
    var isPickingSource = false
    var sourcePoint: CGPoint?
    var selectedSpot: Int?
    private(set) var savedSpots: [SavedSpot] = []
    var manualKind = "none"
    var manualPoints: [CGPoint] = []
    var manualFeather = 60.0
    var manualFlow = 100.0
    var manualDensity = 100.0
    var manualErase = false
    var luminanceLow = 0.0
    var luminanceHigh = 1.0
    var colorRefine = 50.0
    var colorPoint: CGPoint?

    var selectedMask: UInt32?
    var maskOperation = "new"
    var refinement = 0.0
    var showMaskOverlay = true
    var isPickingObject = false
    private var overlayMaskID: UInt32?
    private var overlays: [UInt32: UIImage] = [:]
    private var closeRequested = false
    private(set) var maskOverlay: UIImage?
    private(set) var tintedPreview: UIImage?
    var displayedImage: UIImage? { showMaskOverlay ? (tintedPreview ?? image) : image }
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
        let id: UInt32; let name: String; let adjust: MaskColorAdjustments; let refine: Double?
    }
    nonisolated struct SavedSpot: Decodable {
        let mode: String; let points: [Point]; let size: Double; let feather: Double; let opacity: Double
        let source_offset: Point?
        struct Point: Decodable { let x: Double; let y: Double }
    }
    nonisolated struct MaskList: Decodable { let masks: [SavedMask]; let spots: [SavedSpot]? }
    nonisolated struct MaskRefine: Encodable, Sendable { let id: UInt32; let value: Double }
    nonisolated struct CatalogSource: Decodable {
        let source: Source
        struct Source: Decodable { let type: String; let path: String? }
    }

    nonisolated struct PreviewRequest: Encodable, Sendable {
        let path: String
        let neutralPerspective = true
        var overlayMask: UInt32? = nil
    }
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
        let values: MaskColorAdjustments
    }
    nonisolated struct Spot: Encodable, Sendable {
        let mode: String
        let points: [[Double]]
        let size: Double; let feather: Double; let opacity: Double
        let source: [Double]?
    }
    nonisolated struct AddedSpotResult: Decodable { let index: Int }
    nonisolated struct SpotUpdate: Encodable, Sendable {
        let index: Int; let mode: String; let size: Double; let feather: Double; let opacity: Double
        let source: [Double]?
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
    func refreshAfterHistory() async {
        guard !busy, folder != nil else { return }
        busy = true; defer { busy = false }
        do {
            try await refreshMasks(); try await refreshImage()
            maskOverlay = nil; overlays.removeAll(); overlayMaskID = nil
            restoreMaskControls()
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
        manualKind = "none"; tintedPreview = nil
        isPickingObject = false
        run("Selecting on device…") {
            guard let preview = self.preview else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
            let selection = try await Task.detached(priority: .userInitiated) {
                try OnDeviceAnalysis.selection(at: preview, people: people, background: background, point: point)
            }.value
            try Task.checkCancellation()
            let name = point != nil ? "Object" : (people ? "People" : (background ? "Background" : "Subject"))
            let text = try await self.model.performPhotoEdit("ilightcraft.maskFromAlpha", params: SelectionRequest(
                side: selection.side, alpha: selection.alpha, name: name, maskID: self.maskOperation == "new" ? nil : self.selectedMask, op: self.maskOperation
            ))
            self.selectedMask = try JSONDecoder().decode(MaskResult.self, from: Data(text.utf8)).activeMask
            self.exposure = 0
            if self.maskOperation == "new" { self.overlayMaskID = self.selectedMask; self.maskOverlay = Self.overlay(selection) }
            else { self.maskOverlay = nil }
            if self.maskOverlay != nil { self.showMaskOverlay = true }
            if let id = self.selectedMask {
                self.overlays[id] = self.maskOverlay
                self.overlayMaskID = id
            }
            try await self.refreshMasks()
            try await self.refreshImage()
            self.status = "\(name) mask created. Adjust its exposure below."
        }
    }
    func selectSky() {
        manualKind = "none"; tintedPreview = nil
        isPickingObject = false
        run("Selecting sky on device…") {
            guard let preview = self.preview else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
            let selection = try await Task.detached(priority: .userInitiated) { try PortraitSelections.sky(at: preview) }.value
            try Task.checkCancellation()
            try await self.saveSelection(selection, name: "Sky", operation: self.maskOperation)
            try await self.refreshImage()
            self.status = "Sky mask created. Check the overlay and adjust its exposure."
        }
    }

    func selectIndividuals(skin: Bool) {
        manualKind = "none"; tintedPreview = nil
        isPickingObject = false
        run(skin ? "Selecting each person's skin…" : "Selecting individual people…") {
            guard let preview = self.preview else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
            let selections = try await Task.detached(priority: .userInitiated) { try PortraitSelections.people(at: preview, skin: skin) }.value
            try Task.checkCancellation()
            // Each result is always a new mask, never accidentally combined with another person.
            for result in selections {
                try Task.checkCancellation()
                try await self.saveSelection(result.selection, name: result.name, operation: "new")
            }
            self.maskOperation = "new"
            try await self.refreshImage()
            self.status = "Created \(selections.count) separate \(skin ? "skin" : "person") masks, numbered left to right. Choose one from Saved mask."
        }
    }

    private func saveSelection(_ selection: OnDeviceAnalysis.Selection, name: String, operation: String) async throws {
        let text = try await model.performPhotoEdit("ilightcraft.maskFromAlpha", params: SelectionRequest(
            side: selection.side, alpha: selection.alpha, name: name,
            maskID: operation == "new" ? nil : selectedMask, op: operation
        ))
        selectedMask = try JSONDecoder().decode(MaskResult.self, from: Data(text.utf8)).activeMask
        exposure = 0
        overlayMaskID = selectedMask
        maskOverlay = operation == "new" ? Self.overlay(selection) : nil
        if maskOverlay != nil { showMaskOverlay = true }
        if let selectedMask { overlays[selectedMask] = maskOverlay }
        try await refreshMasks()
    }

    func applyMaskAdjustments() {
        guard let id = selectedMask else { return }
        let values = maskColor
        guard values.isValid else { error = "Choose valid mask color values before applying."; return }
        run("Applying mask adjustments…") {
            _ = try await self.model.performPhotoEdit("mask.adjust", params: MaskAdjustment(id: id, values: values))
            self.showMaskOverlay = false
            try await self.refreshImage()
            try await self.refreshMasks()
            self.status = "Mask adjustments saved. Each mask keeps its own color."
        }
    }
    func colorizeMask(hue: Double) {
        guard !busy, selectedMask != nil else { return }
        maskColor.colorize(hue: hue)
        applyMaskAdjustments()
    }
    func resetMaskColor() {
        guard !busy, selectedMask != nil else { return }
        maskColor.resetColor()
        applyMaskAdjustments()
    }
    func restoreMaskControls() {
        guard let mask = masks.first(where: { $0.id == selectedMask }) else { return }
        maskColor = mask.adjust; refinement = mask.refine ?? 0
        if selectedMask != overlayMaskID {
            tintedPreview = nil
            maskOverlay = selectedMask.flatMap { overlays[$0] }
            overlayMaskID = selectedMask
        }
    }
    func savedMaskChanged() {
        restoreMaskControls()
        guard !busy else { return }
        run("Loading selected mask…") { try await self.refreshImage() }
    }
    func refineMask() {
        guard let id = selectedMask else { return }
        run("Refining mask edges…") {
            _ = try await self.model.performPhotoEdit("mask.refine", params: MaskRefine(id: id, value: self.refinement))
            try await self.refreshMasks(); try await self.refreshImage()
            self.maskOverlay = nil; self.overlays.removeValue(forKey: id); self.status = "Edge refinement saved."
        }
    }
    func invertMask() {
        guard let id = selectedMask else { return }
        run("Inverting mask…") {
            _ = try await self.model.performPhotoEdit("mask.invert", params: ["id": id])
            self.maskOverlay = nil; self.overlays.removeValue(forKey: id); try await self.refreshImage()
        }
    }
    func deleteMask() {
        guard let id = selectedMask else { return }
        run("Deleting mask…") {
            _ = try await self.model.performPhotoEdit("mask.delete", params: ["id": id])
            self.overlays.removeValue(forKey: id)
            self.selectedMask = nil; self.maskOverlay = nil; self.maskOperation = "new"
            try await self.refreshMasks(); try await self.refreshImage()
        }
    }
    private func refreshMasks() async throws {
        let text = try await model.photoCommand("develop.get", params: [String: String]())
        let decoded = try JSONDecoder().decode(MaskList.self, from: Data(text.utf8))
        masks = decoded.masks
        let spots = decoded.spots ?? []
        guard spots.count <= 4096, spots.allSatisfy({ $0.points.count <= 2048 }) else { throw EngineError.engine("Too many saved removal strokes") }
        savedSpots = spots
        if let selectedSpot, !spots.indices.contains(selectedSpot) { self.selectedSpot = nil }
        if let selectedMask, !masks.contains(where: { $0.id == selectedMask }) {
            self.selectedMask = masks.first?.id
        }
        if selectedMask == nil { maskColor = .init(); maskOverlay = nil; tintedPreview = nil; overlayMaskID = nil }
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

    nonisolated struct ManualMaskRequest: Encodable, Sendable {
        let kind: String; let name: String; let operation: String; let id: UInt32?
        var points: [[Double]]?
        var start: [Double]?; var end: [Double]?; var center: [Double]?
        var rx: Double?; var ry: Double?
        var size: Double; var feather: Double; var flow: Double; var density: Double; var erase: Bool
        var lo: Double; var hi: Double; var refine: Double
        var colorPoint: [Double]?
        var loFeather: Double = 0.1; var hiFeather: Double = 0.1
    }
    func beginManual(_ kind: String) {
        guard !busy else { return }
        manualKind = kind; manualPoints = []; colorPoint = nil; isPickingObject = false
    }
    func manualPick(_ point: CGPoint) {
        guard !busy else { return }
        colorPoint = point
    }
    func applyManualMask() {
        guard !busy, manualKind != "none", let image else { return }
        guard maskOperation == "new" || selectedMask != nil else { error = "Choose a mask for this operation."; return }
        let pts = manualPoints.prefix(2048).map { [Double($0.x), Double($0.y)] }
        var request = ManualMaskRequest(kind: manualKind, name: manualKind == "brush" ? "Brush" : manualKind,
                                        operation: maskOperation, id: maskOperation == "new" ? nil : selectedMask,
                                        size: brushSize, feather: manualFeather, flow: manualFlow, density: manualDensity,
                                        erase: manualErase, lo: min(luminanceLow, luminanceHigh), hi: max(luminanceLow, luminanceHigh),
                                        refine: colorRefine)
        request.loFeather = manualFeather / 100; request.hiFeather = manualFeather / 100
        if manualKind == "brush" {
            guard !pts.isEmpty else { error = "Draw a brush stroke on the main photo."; return }
            request.points = pts
        } else if manualKind == "linear" || manualKind == "radial" {
            guard let a = manualPoints.first, let b = manualPoints.last, manualPoints.count >= 2,
                  hypot(a.x - b.x, a.y - b.y) > 0.01 else { error = "Draw the selection on the main photo."; return }
            request.start = [Double(a.x), Double(a.y)]; request.end = [Double(b.x), Double(b.y)]
            request.center = request.start
            let longEdge = max(image.size.width, image.size.height)
            request.rx = Double(max(0.005, abs(b.x - a.x) * image.size.width / longEdge))
            request.ry = Double(max(0.005, abs(b.y - a.y) * image.size.height / longEdge))
        } else if manualKind == "colorRange" {
            guard let colorPoint else { error = "Tap a color on the main photo first."; return }
            request.colorPoint = [Double(colorPoint.x), Double(colorPoint.y)]
        }
        let saved = request
        run("Applying manual selection…") {
            let result = try await self.model.performPhotoEdit("ilightcraft.manualMask", params: saved)
            self.selectedMask = try JSONDecoder().decode(MaskResult.self, from: Data(result.utf8)).activeMask
            self.maskOverlay = nil; self.overlayMaskID = nil; self.manualPoints = []
            self.showMaskOverlay = true
            try await self.refreshMasks(); try await self.refreshImage()
            self.status = "Manual mask saved. Adjust its color or exposure below."
        }
    }

    func removeStroke() {
        guard !stroke.isEmpty else { return }
        let points = stroke.map { [Double(min(1, max(0, $0.x))), Double(min(1, max(0, $0.y)))] }
        guard points.count <= 2048 else { error = "Use a shorter removal stroke."; return }
        let source = sourceOffset(for: stroke.first)
        let request = Spot(mode: removalMode, points: points, size: brushSize, feather: removalFeather, opacity: removalOpacity, source: source)
        run("Applying repair…") {
            let result = try await self.model.performPhotoEdit("spot.add", params: request)
            self.selectedSpot = try JSONDecoder().decode(AddedSpotResult.self, from: Data(result.utf8)).index
            self.stroke = []
            try await self.refreshImage()
            try await self.refreshMasks()
            self.status = "Repair saved. Choose another source or adjust the saved repair below."
        }
    }
    private func sourceOffset(for target: CGPoint?) -> [Double]? {
        guard let sourcePoint, let target else { return nil }
        return [Double(sourcePoint.x - target.x), Double(sourcePoint.y - target.y)]
    }
    func restoreSpotControls() {
        guard let selectedSpot, savedSpots.indices.contains(selectedSpot), let spot = savedSpots.dropFirst(selectedSpot).first else { return }
        removalMode = spot.mode; brushSize = spot.size; removalFeather = spot.feather; removalOpacity = spot.opacity
        if let target = spot.points.first, let offset = spot.source_offset {
            sourcePoint = CGPoint(x: target.x + offset.x, y: target.y + offset.y)
        } else { sourcePoint = nil }
        isPickingSource = false
    }
    func updateSavedSpot() {
        guard let selectedSpot, savedSpots.indices.contains(selectedSpot), let spot = savedSpots.dropFirst(selectedSpot).first else { return }
        let target = spot.points.first.map { CGPoint(x: $0.x, y: $0.y) }
        let request = SpotUpdate(index: selectedSpot, mode: removalMode, size: brushSize, feather: removalFeather, opacity: removalOpacity, source: sourceOffset(for: target))
        run("Updating repair…") {
            _ = try await self.model.performPhotoEdit("spot.update", params: request)
            try await self.refreshImage(); try await self.refreshMasks()
        }
    }
    func changeSpotSource() {
        guard let selectedSpot else { return }
        run("Finding another source…") {
            _ = try await self.model.performPhotoEdit("spot.refreshSource", params: ["index": selectedSpot])
            try await self.refreshImage(); try await self.refreshMasks(); self.restoreSpotControls()
        }
    }
    func deleteSavedSpot() {
        guard let selectedSpot else { return }
        run("Restoring repaired area…") {
            _ = try await self.model.performPhotoEdit("spot.delete", params: ["index": selectedSpot])
            self.selectedSpot = nil; self.sourcePoint = nil
            try await self.refreshImage(); try await self.refreshMasks()
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
                _ = try await self.model.photoCommand("ilightcraft.cropPreview", params: params)
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
        _ = try await model.photoCommand("ilightcraft.cropPreview", params: PreviewRequest(path: url.path))
        let data = try await Task.detached { try Data(contentsOf: url) }.value
        guard let image = UIImage(data: data) else { throw OnDeviceAnalysis.AnalysisError.imageUnavailable }
        if let old = preview { try? FileManager.default.removeItem(at: old) }
        preview = url
        self.image = image
        tintedPreview = nil
        if let id = selectedMask, masks.contains(where: { $0.id == id }) {
            let overlayURL = folder.appending(path: "overlay-\(UUID()).png")
            defer { try? FileManager.default.removeItem(at: overlayURL) }
            _ = try await model.photoCommand("ilightcraft.cropPreview", params: PreviewRequest(path: overlayURL.path, overlayMask: id))
            let overlayData = try await Task.detached { try Data(contentsOf: overlayURL) }.value
            tintedPreview = UIImage(data: overlayData)
        }
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
