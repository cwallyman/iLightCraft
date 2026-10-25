//
//  EnhancementSession.swift
//  iLightCraft
//

import Foundation
import Observation

/// EnhancementSession makes optional-model RGB restoration explicit and keeps the source edit intact.
@Observable
@MainActor
final class EnhancementSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    var mode = EnhancementModel.denoise
    private(set) var installed = Set(EnhancementModel.allCases.filter { $0.installed != nil })
    private(set) var busy = false
    private(set) var progress = 0.0
    private(set) var status = ""
    var error: String?
    private let model: EditorViewModel<Engine, Importer>
    private let onOpen: @MainActor (URL) async -> Void
    private var task: Task<Void, Never>?
    nonisolated struct Unpack: Encodable, Sendable { let archive: String; let destination: String; let variant: String }
    nonisolated struct Export: Encodable, Sendable { let path: String; let format = "png"; let metadata = "none" }
    init(model: EditorViewModel<Engine, Importer>, onOpen: @escaping @MainActor (URL) async -> Void) {
        self.model = model; self.onOpen = onOpen
    }
    func cancel() { task?.cancel() }
    func download() {
        guard !busy else { return }
        let mode = mode
        busy = true; error = nil; progress = 0; status = "Downloading approximately 2.3 MB…"
        task = Task {
            defer { busy = false }
            let staging = URL.temporaryDirectory.appending(path: "enhancement-model-\(UUID())")
            defer { try? FileManager.default.removeItem(at: staging) }
            do {
                let archive = try await mode.download()
                defer { try? FileManager.default.removeItem(at: archive) }
                try Task.checkCancellation()
                status = "Checking and unpacking model…"
                _ = try await model.photoCommand("ilightcraft.unpackEnhancement", params: Unpack(archive: archive.path, destination: staging.path, variant: mode.rawValue))
                status = "Compiling on-device model…"
                try await mode.compile(packageURL: staging.appending(path: mode.package))
                installed.insert(mode); status = "Model installed. Processing stays on device."
            } catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
        }
    }
    func removeModel() {
        guard !busy else { return }
        do { try mode.remove(); installed.remove(mode); status = "Downloaded model removed. Originals unchanged." }
        catch { self.error = error.localizedDescription }
    }
    func render() {
        guard !busy, installed.contains(mode) else { return }
        guard !model.hdrEnabled else { error = "RGB enhancement is SDR-only. Disable HDR Editing explicitly first; the source stays intact."; return }
        let mode = mode
        busy = true; error = nil; progress = 0; status = "Preparing SDR render…"
        task = Task {
            defer { busy = false }
            let source = URL.temporaryDirectory.appending(path: "enhancement-input-\(UUID()).png")
            let result = URL.temporaryDirectory.appending(path: "iLightCraft-\(mode.rawValue)-\(UUID()).png")
            defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: result) }
            do {
                _ = try await model.photoCommand("ilightcraft.export", params: Export(path: source.path))
                try Task.checkCancellation()
                status = "Restoring padded tiles on device…"
                let work = Task.detached(priority: .userInitiated) {
                    try TiledEnhancement.render(source: source, destination: result, mode: mode) { @Sendable fraction in
                        Task { @MainActor in self.progress = fraction }
                    }
                }
                try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                status = "Opening the enhanced copy. Source retained."
                await onOpen(result)
            } catch is CancellationError { status = "Cancelled. Source retained." }
            catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
        }
    }
}
