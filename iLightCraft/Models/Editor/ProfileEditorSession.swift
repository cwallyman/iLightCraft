import Foundation
import Observation
import UIKit

nonisolated struct NativeProfile: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let group: String
    let favorite: Bool
    var imported: Bool?
}

nonisolated struct NativeProfileMenu: Decodable, Sendable {
    struct Group: Decodable, Sendable {
        let name: String
        let profiles: [NativeProfile]
    }
    let favorites: [NativeProfile]
    let recent: [NativeProfile]
    let groups: [Group]
}

@Observable
@MainActor
final class ProfileEditorSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    private(set) var menu: NativeProfileMenu?
    private(set) var selectedID = ""
    var amount = 100.0
    private var savedAmount = 100.0
    private(set) var busy = false
    private(set) var loaded = false
    private(set) var preview: UIImage?
    var error: String?
    private var showsPreview = false

    nonisolated struct Settings: Decodable {
        let profile: Profile
        struct Profile: Decodable {
            let id: String
            let amount: Double
        }
    }
    nonisolated struct SetRequest: Encodable, Sendable { let id: String; let amount: Double }
    nonisolated struct FavoriteRequest: Encodable, Sendable { let id: String; let favorite: Bool }

    init(model: EditorViewModel<Engine, Importer>) { self.model = model }
    var currentName: String {
        menu?.groups.lazy.flatMap(\.profiles).first(where: { $0.id == selectedID })?.name ?? selectedID
    }
    func load(showsPreview: Bool) async {
        guard !busy else { return }
        self.showsPreview = showsPreview
        busy = true; defer { busy = false }
        do {
            try await readSettings(); try await readMenu(); loaded = true
            try await refreshPreview()
        } catch { self.error = Self.message(error) }
    }
    private func readSettings() async throws {
        let text = try await model.photoCommand("develop.get", params: [String: String]())
        let value = try JSONDecoder().decode(Settings.self, from: Data(text.utf8)).profile
        guard !value.id.isEmpty, value.id.count <= 512, value.amount.isFinite, (0...200).contains(value.amount) else {
            throw EngineError.engine("The photo's profile settings are invalid")
        }
        selectedID = value.id
        amount = value.amount; savedAmount = value.amount
    }
    private func readMenu() async throws {
        let text = try await model.photoCommand("profiles.menu", params: [String: String]())
        let menu = try JSONDecoder().decode(NativeProfileMenu.self, from: Data(text.utf8))
        guard menu.groups.count <= 128, menu.groups.reduce(0, { $0 + $1.profiles.count }) <= 4096 else {
            throw EngineError.engine("The profile list is too large to display")
        }
        self.menu = menu
    }
    func select(_ profile: NativeProfile) async {
        guard loaded, !busy, profile.id != selectedID else { return }
        await apply(id: profile.id, amount: amount)
    }
    func commitAmount() async {
        guard loaded, !busy, amount.isFinite else { return }
        let value = min(200, max(0, amount.rounded()))
        guard value != savedAmount else { return }
        await apply(id: selectedID, amount: value)
    }
    func reset() async {
        guard loaded, !busy else { return }
        await apply(id: "lc.color", amount: 100)
    }
    private func apply(id: String, amount: Double) async {
        guard !busy, !id.isEmpty, amount.isFinite, (0...200).contains(amount) else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await model.performPhotoEdit("develop.profile", params: SetRequest(id: id, amount: amount))
            try await readSettings(); try await readMenu()
            try await refreshPreview()
        } catch {
            self.error = Self.message(error)
            try? await readSettings()
        }
    }
    func favorite(_ profile: NativeProfile) async {
        guard loaded, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await model.photoCommand("profile.favorite", params: FavoriteRequest(id: profile.id, favorite: !profile.favorite))
            try await readMenu()
        } catch { self.error = Self.message(error) }
    }
    func undo(redo: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        if redo { await model.redo() } else { await model.undo() }
        do { try await readSettings(); try await readMenu(); try await refreshPreview() }
        catch { self.error = Self.message(error) }
    }
    private func refreshPreview() async throws {
        guard showsPreview else { return }
        let url = URL.temporaryDirectory.appending(path: "profile-preview-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await model.photoCommand("ilightcraft.export", params: ToneCurveSession<Engine, Importer>.PreviewRequest(path: url.path))
        let bytes = try await Task.detached { try Data(contentsOf: url) }.value
        guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read the profile preview") }
        preview = image
    }
    private static func message(_ error: Error) -> String { (error as? EngineError)?.message ?? error.localizedDescription }
}
