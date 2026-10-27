//
//  PhotoPanelSession.swift
//  iLightCraft
//

import Foundation
import Observation
import UIKit

nonisolated enum PhotoPanelMode: String, CaseIterable, Identifiable {
    case photoGrid, squareGrid, detail, compare, survey, beforeAfter
    var id: String { rawValue }
    var title: String {
        switch self {
        case .photoGrid: "Photo Grid"
        case .squareGrid: "Square Grid"
        case .detail: "Single Photo"
        case .compare: "Compare"
        case .survey: "Survey"
        case .beforeAfter: "Before / Edited"
        }
    }
    var icon: String {
        switch self {
        case .photoGrid: "GridPhoto"
        case .squareGrid: "GridSquare"
        case .detail: "Single"
        case .compare: "Compare"
        case .survey: "Survey"
        case .beforeAfter: "BeforeAfter"
        }
    }
}

/// PhotoPanelSession drives the desktop-style view, sorting, culling and settings strip.
@Observable @MainActor
final class PhotoPanelSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    typealias Photo = PhotoMergeSession<Engine, Importer>.Photo
    let model: EditorViewModel<Engine, Importer>
    var mode: PhotoPanelMode = .detail
    private(set) var beforeImage: UIImage?
    private(set) var editedImage: UIImage?
    private(set) var comparisonLoading = false
    private(set) var comparisonError: String?
    @ObservationIgnored private var comparisonTask: Task<Void, Never>?
    @ObservationIgnored private var comparisonGeneration: UInt64 = 0
    @ObservationIgnored private var comparisonPhoto: PhotoID?
    var selected: [UInt64] = []
    var groups = NativeSettingsGroup.defaults
    var sortKey = "captureDate"
    var ascending = true
    var groupBy = "auto"
    private(set) var rating = 0
    private(set) var flag = "none"
    private(set) var hasClipboard = false
    private(set) var photos: [Photo] = []
    private(set) var total = 0
    private(set) var busy = false
    var error: String?
    var status = ""
    @ObservationIgnored private let thumbnails = NSCache<NSNumber, UIImage>()
    nonisolated struct PhotoState: Decodable { let rating: Int; let flag: String; let source: Source }
    nonisolated struct Source: Decodable { let path: String? }
    nonisolated struct LibraryState: Decodable {
        let clipboard: Bool
        let sort: Sort
        struct Sort: Decodable { let key: String; let ascending: Bool; let group: String }
    }
    nonisolated struct Copy: Encodable, Sendable { let groups: [String]; let ids: [UInt64]? }
    nonisolated struct Preview: Encodable, Sendable {
        let id: UInt64; let path: String; let longEdge: Int
        let format = "jpeg"; let quality = 85; let metadata = "none"; let colorSpace = "srgb"
    }
    init(model: EditorViewModel<Engine, Importer>) {
        self.model = model
        thumbnails.totalCostLimit = 48 * 1024 * 1024
        thumbnails.countLimit = 128
    }
    func load() async {
        guard !busy, model.isPhotoOpen else { return }
        busy = true; defer { busy = false }
        do { try await read() } catch { self.error = error.localizedDescription }
    }
    private func read() async throws {
        let text = try await model.photoCommand("photo.inspect", params: [String: String]())
        let photo = try JSONDecoder().decode(PhotoState.self, from: Data(text.utf8))
        rating = photo.rating; flag = photo.flag
        let library = try await model.photoCommand("library.state", params: [String: String]())
        let state = try JSONDecoder().decode(LibraryState.self, from: Data(library.utf8))
        hasClipboard = state.clipboard
        sortKey = state.sort.key; ascending = state.sort.ascending; groupBy = state.sort.group
    }
    func choose(_ mode: PhotoPanelMode) async {
        guard !busy else { return }
        self.mode = mode
        if mode == .beforeAfter { return }
        stopComparison()
        if selected.isEmpty, let id = model.openPhoto?.rawValue { selected = [id] }
        if mode == .compare { selected = Array(selected.prefix(2)) }
        if mode != .detail { await reloadPhotos() }
    }
    nonisolated private struct ComparisonPreview: Encodable, Sendable {
        let id: UInt64; let path: String; let before: Bool
        let longEdge = 1400
    }
    func stopComparison() {
        comparisonGeneration &+= 1; comparisonTask?.cancel(); comparisonTask = nil
        beforeImage = nil; editedImage = nil; comparisonPhoto = nil
        comparisonLoading = false; comparisonError = nil
    }
    /// requestComparison replaces stale preview work without touching saved photo settings.
    func requestComparison() {
        guard mode == .beforeAfter, let photo = model.openPhoto else { return }
        comparisonTask?.cancel(); comparisonGeneration &+= 1
        let generation = comparisonGeneration
        if comparisonPhoto != photo { beforeImage = nil; editedImage = nil }
        comparisonLoading = true; comparisonError = nil
        comparisonTask = Task {
            let beforeFile = URL.temporaryDirectory.appending(path: "before-\(UUID()).png")
            let editedFile = URL.temporaryDirectory.appending(path: "edited-\(UUID()).png")
            defer {
                try? FileManager.default.removeItem(at: beforeFile); try? FileManager.default.removeItem(at: editedFile)
                if generation == self.comparisonGeneration { self.comparisonLoading = false }
            }
            do {
                await self.model.finishPendingEdits()
                try Task.checkCancellation()
                let settings = try await self.model.photoCommand("develop.get", params: [String: String]())
                _ = try await self.model.photoCommand("ilightcraft.comparisonPreview", params: ComparisonPreview(id: photo.rawValue, path: beforeFile.path, before: true))
                try Task.checkCancellation()
                guard self.model.openPhoto == photo else { return }
                _ = try await self.model.photoCommand("ilightcraft.comparisonPreview", params: ComparisonPreview(id: photo.rawValue, path: editedFile.path, before: false))
                try Task.checkCancellation()
                let latest = try await self.model.photoCommand("develop.get", params: [String: String]())
                guard self.mode == .beforeAfter, self.model.openPhoto == photo,
                      generation == self.comparisonGeneration, settings == latest else { return }
                let bytes = try await Task.detached {
                    let a = try beforeFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    let b = try editedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard a > 0, b > 0, a <= 32_000_000, b <= 32_000_000 else { throw EngineError.engine("Comparison preview is too large") }
                    return (try Data(contentsOf: beforeFile), try Data(contentsOf: editedFile))
                }.value
                try Task.checkCancellation()
                guard let before = UIImage(data: bytes.0), let edited = UIImage(data: bytes.1) else { throw EngineError.engine("Cannot read comparison previews") }
                guard generation == self.comparisonGeneration else { return }
                self.beforeImage = before; self.editedImage = edited; self.comparisonPhoto = photo
            } catch is CancellationError {
            } catch {
                if generation == self.comparisonGeneration { self.comparisonError = error.localizedDescription }
            }
        }
    }
    func toggleSelection(_ id: UInt64) {
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) }
        else if selected.count < (mode == .compare ? 2 : 8) { selected.append(id) }
        else if mode == .compare, selected.count == 2 { selected[1] = id }
    }
    func reloadPhotos() async {
        photos = []; thumbnails.removeAllObjects()
        await loadMore()
    }
    func loadMore() async {
        guard !busy, photos.count < 1000 else { return }
        busy = true; defer { busy = false }
        do {
            let text = try await model.photoCommand("catalog.query", params: ["offset": photos.count, "limit": 50])
            let page = try JSONDecoder().decode(PhotoMergeSession<Engine, Importer>.Page.self, from: Data(text.utf8))
            let known = Set(photos.map(\.id))
            photos += await Photo.resolvingNames(page.photos.filter { !known.contains($0.id) })
            total = page.total
        } catch { self.error = error.localizedDescription }
    }
    func setRating(_ value: Int) async {
        guard (0...5).contains(value), let id = model.openPhoto?.rawValue else { return }
        await metadata("photo.rate", params: Rating(rating: value, ids: [id]))
    }
    nonisolated struct Rating: Encodable, Sendable { let rating: Int; let ids: [UInt64] }
    nonisolated struct Flag: Encodable, Sendable { let flag: String; let ids: [UInt64] }
    func setFlag(_ value: String) async {
        guard ["none", "pick", "reject"].contains(value), let id = model.openPhoto?.rawValue else { return }
        await metadata("photo.flag", params: Flag(flag: value, ids: [id]))
    }
    private func metadata(_ command: String, params: some Encodable & Sendable) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do { _ = try await model.photoCommand(command, params: params); try await read() }
        catch { self.error = error.localizedDescription }
    }
    func sort(_ key: String? = nil, ascending: Bool? = nil, group: String? = nil) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await model.photoCommand("library.sort", params: Sort(key: key, ascending: ascending, group: group))
            try await read()
            busy = false
            if mode != .detail { await reloadPhotos() }
        } catch { self.error = error.localizedDescription }
    }
    nonisolated struct Sort: Encodable, Sendable { let key: String?; let ascending: Bool?; let group: String? }
    func shuffle() async {
        do { _ = try await model.photoCommand("library.shuffle", params: [String: String]()); await reloadPhotos() }
        catch { self.error = error.localizedDescription }
    }
    func copyOrPaste(copyOnly: Bool = false) async {
        guard !busy, !groups.isEmpty else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            let copy = copyOnly || !hasClipboard
            let ids = copy ? nil : model.openPhoto.map { [$0.rawValue] }
            let params = Copy(groups: groups.map(\.rawValue).sorted(), ids: ids)
            if copy { _ = try await model.photoCommand("develop.copy", params: params) }
            else { _ = try await model.performPhotoEdit("develop.paste", params: params); thumbnails.removeAllObjects() }
            status = copy ? "Edit settings copied" : "Settings pasted"
            try await read()
        } catch { self.error = error.localizedDescription }
    }
    func source(for id: UInt64) async throws -> URL {
        let text = try await model.photoCommand("photo.inspect", params: ["id": id])
        let photo = try JSONDecoder().decode(PhotoState.self, from: Data(text.utf8))
        guard let path = photo.source.path else { throw EngineError.engine("This photo has no local source file") }
        return URL(filePath: path)
    }
    func thumbnail(_ id: UInt64, large: Bool = false) async throws -> UIImage {
        if !large, let image = thumbnails.object(forKey: NSNumber(value: id)) { return image }
        let file = URL.temporaryDirectory.appending(path: "photo-panel-\(UUID()).jpg")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = try await model.photoCommand("ilightcraft.export", params: Preview(id: id, path: file.path, longEdge: large ? 1400 : 320))
        try Task.checkCancellation()
        let bytes = try await Task.detached { try Data(contentsOf: file) }.value
        guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read photo preview") }
        if !large { thumbnails.setObject(image, forKey: NSNumber(value: id), cost: Int(image.size.width * image.size.height) * 4) }
        return image
    }
}
