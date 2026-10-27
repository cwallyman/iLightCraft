//
//  PhotoMergeSession.swift
//  iLightCraft
//

import Foundation
import Observation

/// PhotoMergeSession keeps source order, polls a cancellable worker and opens only its new catalog result.
@Observable
@MainActor
final class PhotoMergeSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    nonisolated struct Photo: Decodable, Identifiable, Sendable {
        let id: UInt64
        let fileName: String
        let width: Int
        let height: Int
        let title: String?
        let copyName: String?
        var captured: String? = nil
        var originalName: String?
        var name: String {
            let base = title.flatMap { $0.isEmpty ? nil : $0 } ?? Self.withoutImportHash(originalName ?? fileName)
            let suffix = copyName.flatMap { $0.isEmpty ? nil : $0 }.map { " (\($0))" } ?? ""
            return base + suffix
        }
        private static func withoutImportHash(_ name: String) -> String {
            let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
            let prefix = stem.prefix(64)
            if prefix.count == 64, prefix.allSatisfy({ $0.isHexDigit }), stem.dropFirst(64).first == "-" {
                return String(stem.dropFirst(65))
            }
            return stem
        }
        static func resolvingNames(_ photos: [Self]) async -> [Self] {
            await Task.detached(priority: .utility) {
                photos.map { original in
                    var photo = original
                    let file = PhotoImporter.defaultDirectory.appending(path: URL(filePath: photo.fileName).lastPathComponent)
                    photo.originalName = (try? NativeImageInfo.read(for: file))?.originalFileName
                    return photo
                }
            }.value
        }
    }
    nonisolated struct Page: Decodable { let total: Int; let photos: [Photo] }
    nonisolated struct Status: Decodable {
        let state: String
        let progress: Double?
        let stage: String?
        let error: String?
        let result: Result?
        struct Result: Decodable { let id: UInt64; let path: String }
    }
    nonisolated struct Request: Encodable, Sendable {
        let ids: [UInt64]
        let kind: String
        let deghost: String
        let projection: String
        let autoCrop: Bool
        let maxMegapixels: Double
        let availableBytes: UInt64
        let align = true
        let autoSettings = true
        let bracket = 0
    }
    var kind = "hdr"
    var deghost = "medium"
    var projection = "auto"
    var autoCrop = true
    var maxMegapixels = 20.0
    var selected: [UInt64] = []
    private(set) var photos: [Photo] = []
    private(set) var total = 0
    private(set) var working = false
    private(set) var progress = 0.0
    private(set) var stage = ""
    var error: String?
    private let model: EditorViewModel<Engine, Importer>
    private let onOpen: @MainActor (PhotoID, URL) async -> Void

    init(model: EditorViewModel<Engine, Importer>, onOpen: @escaping @MainActor (PhotoID, URL) async -> Void) {
        self.model = model
        self.onOpen = onOpen
    }
    func loadMore() async {
        do {
            let text = try await model.photoCommand("catalog.query", params: ["offset": photos.count, "limit": 50])
            let page = try JSONDecoder().decode(Page.self, from: Data(text.utf8))
            let existing = Set(photos.map(\.id))
            photos += await Photo.resolvingNames(page.photos.filter { !existing.contains($0.id) })
            total = page.total
        } catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
    }
    func toggle(_ id: UInt64) {
        guard !working else { return }
        if let index = selected.firstIndex(of: id) { selected.remove(at: index) }
        else if selected.count < 12 { selected.append(id) }
    }
    func cancel() async {
        do {
            _ = try await model.photoCommand("ilightcraft.mergeCancel", params: [String: String]())
            stage = "Cancelling at the next processing boundary…"
        } catch { self.error = error.message }
    }
    func merge() async {
        guard !working, selected.count >= 2 else { return }
        working = true; error = nil; progress = 0
        stage = "Preparing source photos…"
        defer { working = false }
        do {
            let available = ProcessAvailableMemory().availableBytes()
            _ = try await model.photoCommand("ilightcraft.mergeStart", params: Request(
                ids: selected, kind: kind, deghost: deghost, projection: projection,
                autoCrop: autoCrop, maxMegapixels: maxMegapixels, availableBytes: available
            ))
            while true {
                try await Task.sleep(for: .milliseconds(350))
                let text = try await model.photoCommand("ilightcraft.mergeStatus", params: [String: String]())
                let status = try JSONDecoder().decode(Status.self, from: Data(text.utf8))
                switch status.state {
                case "completed":
                    guard let result = status.result else { throw EngineError.engine("Merge completed without a catalog result") }
                    progress = 1; stage = "New merged DNG saved. Originals retained."
                    await onOpen(PhotoID(rawValue: result.id), URL(filePath: result.path))
                    return
                case "idle": stage = "Merge stopped while the app was inactive. Sources retained."; return
                case "cancelled": stage = "Merge cancelled. Originals retained."; return
                case "failed": throw EngineError.engine(status.error ?? "Merge failed")
                default: progress = status.progress ?? progress; stage = status.stage ?? stage
                }
            }
        } catch is CancellationError {
            _ = try? await model.photoCommand("ilightcraft.mergeCancel", params: [String: String]())
            stage = "Cancellation requested. Originals retained."
        } catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
    }
}
