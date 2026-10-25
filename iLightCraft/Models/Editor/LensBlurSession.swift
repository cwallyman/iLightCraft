//
//  LensBlurSession.swift
//  iLightCraft
//

import Foundation
import Observation

/// LensBlurSession creates an explicit derived copy; it never replaces a source Photos item.
@Observable
@MainActor
final class LensBlurSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    var amount = 25.0
    var focus = 0.5
    var range = 0.15
    private(set) var installed = DepthModelStore.installed != nil
    private(set) var busy = false
    private(set) var status = ""
    var error: String?
    private let model: EditorViewModel<Engine, Importer>
    private let onOpen: @MainActor (URL) async -> Void
    private var task: Task<Void, Never>?
    nonisolated struct Export: Encodable, Sendable {
        let path: String
        let format = "tiff"
        let bitDepth = 32
        let colorSpace = "srgb"
        let metadata = "none"
    }
    init(model: EditorViewModel<Engine, Importer>, onOpen: @escaping @MainActor (URL) async -> Void) {
        self.model = model; self.onOpen = onOpen
    }
    func cancel() { task?.cancel() }
    func removeModel() {
        guard !busy else { return }
        do { try DepthModelStore.remove(); installed = false; status = "Downloaded model removed. Photo files are unchanged." }
        catch { self.error = error.localizedDescription }
    }
    func download() {
        guard !busy else { return }
        busy = true; error = nil
        task = Task {
            defer { busy = false }
            do {
                let work = Task.detached(priority: .utility) {
                    try await DepthModelStore.install { @Sendable message in
                        Task { @MainActor in self.status = message }
                    }
                }
                try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                installed = DepthModelStore.installed != nil
            } catch { self.error = error.localizedDescription }
        }
    }
    func render() {
        guard !busy, installed else { return }
        busy = true; error = nil
        let amount = amount, focus = focus, range = range
        task = Task {
            defer { busy = false }
            let temporary = URL.temporaryDirectory.appending(path: "lens-blur-input-\(UUID()).tiff")
            let result = URL.temporaryDirectory.appending(path: "iLightCraft-LensBlur-\(UUID()).tiff")
            defer { try? FileManager.default.removeItem(at: temporary); try? FileManager.default.removeItem(at: result) }
            do {
                status = "Rendering full-resolution source…"
                _ = try await model.photoCommand(model.hdrEnabled ? "ilightcraft.hdrExport" : "ilightcraft.export", params: Export(path: temporary.path))
                try Task.checkCancellation()
                status = "Estimating depth and blurring on device…"
                let work = Task.detached(priority: .userInitiated) {
                    try DepthLensBlur.render(source: temporary, destination: result, amount: amount, focus: focus, range: range)
                }
                try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
                try Task.checkCancellation()
                status = "Opening a new blurred copy. Original retained."
                await onOpen(result)
            } catch is CancellationError { status = "Cancelled. Original retained." }
            catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
        }
    }
}
