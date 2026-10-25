import Foundation
import Observation

@Observable
@MainActor
final class NativeBackupSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    private(set) var busy = false
    private(set) var progress = 0.0
    var status = UserDefaults.standard.string(forKey: "native.recoveryStatus") ?? ""
    var error: String?
    private var operation: Task<Void, Never>?
    private var cancelWork: (@Sendable () -> Void)?
    init(model: EditorViewModel<Engine, Importer>) { self.model = model }
    func cancel() { cancelWork?(); status = "Cancelling after the current file…" }
    func create(at destination: URL) {
        guard !busy else { return }
        busy = true; progress = 0; error = nil; status = "Saving library snapshot…"
        operation = Task {
            let access = destination.startAccessingSecurityScopedResource()
            defer { if access { destination.stopAccessingSecurityScopedResource() }; self.busy = false; self.cancelWork = nil }
            do {
                _ = try await model.photoCommand("library.compact", params: [String: String]())
                let root = NativeLibraryLocation.root
                self.status = "Copying and verifying library files…"
                let work = Task.detached(priority: .utility) {
                    try NativeLibraryBackup.create(root: root, destination: destination) { value in
                        Task { @MainActor in self.progress = value }
                    }
                }
                cancelWork = { work.cancel() }
                let package = try await work.value
                self.status = "Backup verified: \(package.lastPathComponent). Original files are unchanged."
            } catch is CancellationError { self.status = "Backup cancelled; incomplete package removed." }
            catch { self.error = error.localizedDescription }
        }
    }
    func restore(from package: URL) {
        guard !busy else { return }
        busy = true; progress = 0; error = nil; status = "Verifying backup and staging a separate library…"
        operation = Task {
            let access = package.startAccessingSecurityScopedResource()
            defer { if access { package.stopAccessingSecurityScopedResource() }; self.busy = false; self.cancelWork = nil }
            do {
                let work = Task.detached(priority: .utility) {
                    try NativeLibraryBackup.restore(package: package) { value in
                        Task { @MainActor in self.progress = value }
                    }
                }
                cancelWork = { work.cancel() }
                let id = try await work.value
                UserDefaults.standard.set(id, forKey: NativeLibraryLocation.pendingKey)
                self.status = "Recovery verified and staged. Close iLightCraft and reopen to use it. Your current library is retained. Photos links are not transferred."
                UserDefaults.standard.set(self.status, forKey: "native.recoveryStatus")
            } catch is CancellationError { self.status = "Recovery cancelled; the current library is unchanged." }
            catch { self.error = error.localizedDescription }
        }
    }
}
