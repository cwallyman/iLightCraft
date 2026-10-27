import Foundation
import Observation
import UIKit

nonisolated enum NativeSettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case profile, treatment, whiteBalance, light, toneCurve, color, colorMixer, colorGrading
    case effects, vignette, grain, detail, optics, geometry, crop, masks, spots, redEye, lensBlur, calibration
    var id: String { rawValue }
    var title: String {
        switch self {
        case .whiteBalance: "White Balance"
        case .toneCurve: "Tone Curve"
        case .colorMixer: "HSL / Point Color"
        case .colorGrading: "Color Grading"
        case .redEye: "Red Eye"
        case .lensBlur: "Lens Blur"
        default: rawValue.capitalized
        }
    }
    static let defaults = Set(allCases.filter { ![.crop, .masks, .spots, .redEye].contains($0) })
}

@Observable
@MainActor
final class PresetVersionSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    typealias Photo = PhotoMergeSession<Engine, Importer>.Photo
    nonisolated struct Preset: Decodable, Identifiable {
        let id: String; let name: String; let group: String; let favorite: Bool; let builtin: Bool
    }
    nonisolated struct History: Decodable {
        let history: [String]; let versions: [Version]
        struct Version: Decodable { let name: String; let created: String; let auto: Bool? }
    }
    nonisolated struct Snapshot: Codable, Sendable { let id: UInt64; let settingsJSON: String }
    nonisolated struct Restore: Encodable, Sendable { let rows: [Snapshot] }
    nonisolated struct ApplyPreset: Encodable, Sendable { let id: String; let amount: Double; let ids: [UInt64] }
    nonisolated struct CopyPaste: Encodable, Sendable { let groups: [String]; var ids: [UInt64]? = nil }
    nonisolated struct CreatePreset: Encodable, Sendable { let name: String; let group: String; let groups: [String] }
    nonisolated struct Favorite: Encodable, Sendable { let id: String; let favorite: Bool }
    nonisolated struct CopyRequest: Encodable, Sendable { let ids: [UInt64]; let name: String }
    nonisolated struct MadeCopies: Decodable { let ids: [UInt64] }
    nonisolated struct RenameVersion: Encodable, Sendable { let index: Int; let name: String }
    nonisolated struct Export: Encodable, Sendable { let path: String }
    nonisolated struct Preview: Encodable, Sendable {
        let path: String; var id: UInt64? = nil; var index: Int? = nil
        let format = "png"; let longEdge = 1200; let metadata = "none"; let colorSpace = "srgb"
    }
    let model: EditorViewModel<Engine, Importer>
    var name = ""
    var query = ""
    var presetGroupName = "User Presets"
    private(set) var appliedPresetID: String?
    private var presetBaseline: String?
    private var presetExpectedSettings: String?
    private var presetPhoto: PhotoID?
    private var appliedPresetAmount = 100.0
    var favoritesOnly = false
    var amount = 100.0
    var groups = NativeSettingsGroup.defaults
    var selected: Set<UInt64> = []
    private(set) var presets: [Preset] = []
    private(set) var photos: [Photo] = []
    private(set) var total = 0
    private(set) var history: [String] = []
    private(set) var versions: [History.Version] = []
    private(set) var busy = false
    private(set) var referenceImage: UIImage?
    private(set) var referenceName = ""
    private(set) var exportedFile: URL?
    private(set) var canUndoBatch = false
    private(set) var canRedoBatch = false
    var status = ""
    var error: String?
    private var beforeBatch: [Snapshot] = []
    private var afterBatch: [Snapshot] = []
    private let onOpen: @MainActor (PhotoID, URL) async -> Void
    init(model: EditorViewModel<Engine, Importer>, onOpen: @escaping @MainActor (PhotoID, URL) async -> Void) {
        self.model = model; self.onOpen = onOpen
        if let saved = model.presetReplacementState, saved.photo == model.openPhoto {
            appliedPresetID = saved.presetID; presetBaseline = saved.baseline
            presetExpectedSettings = saved.expected; presetPhoto = saved.photo
            amount = saved.amount; appliedPresetAmount = saved.amount
        }
    }
    func load(includePhotos: Bool = true) async {
        await run {
            try await self.refresh()
            if includePhotos && self.photos.isEmpty { try await self.loadMoreImpl() }
        }
    }
    private func refresh() async throws {
        let p = try await model.photoCommand("presets.list", params: [String: String]())
        presets = try JSONDecoder().decode([Preset].self, from: Data(p.utf8))
        guard presets.count <= 20_000 else { throw EngineError.engine("Too many presets to display") }
        let h = try await model.photoCommand("history.list", params: [String: String]())
        let state = try JSONDecoder().decode(History.self, from: Data(h.utf8))
        guard state.history.count <= 10000, state.versions.count <= 1000 else { throw EngineError.engine("History or versions exceed display limits") }
        history = state.history; versions = state.versions
        let inspected = try await model.photoCommand("photo.inspect", params: [String: String]())
        versions = try JSONDecoder().decode(InspectedVersions.self, from: Data(inspected.utf8)).versions
        if let expected = presetExpectedSettings {
            let current = try await model.photoCommand("develop.get", params: [String: String]())
            if model.openPhoto != presetPhoto || current != expected { clearPresetSelection() }
        }
    }
    func loadMore() async { await run { try await self.loadMoreImpl() } }
    private func loadMoreImpl() async throws {
        guard photos.count < 1000 else { throw EngineError.engine("This picker shows up to 1,000 imported photos") }
        let text = try await model.photoCommand("catalog.query", params: ["offset": photos.count, "limit": 50])
        let page = try JSONDecoder().decode(PhotoMergeSession<Engine, Importer>.Page.self, from: Data(text.utf8))
        let existing = Set(photos.map(\.id))
        photos += await Photo.resolvingNames(page.photos.filter { !existing.contains($0.id) })
        total = page.total
    }
    func toggle(_ id: UInt64) {
        guard !busy, id != model.openPhoto?.rawValue else { return }
        if selected.contains(id) { selected.remove(id) }
        else if selected.count < 20 { selected.insert(id) }
        else { error = "Choose at most 20 other photos per batch." }
    }
    func createPreset() async {
        guard validName, presetGroupName.count <= 120, !groups.isEmpty else { error = "Enter a name and choose settings groups."; return }
        let canonical = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().replacingOccurrences(of: " ", with: "-")
        guard !presets.contains(where: { $0.name.lowercased().replacingOccurrences(of: " ", with: "-") == canonical }) else {
            error = "A preset with this name already exists."; return
        }
        await run {
            _ = try await self.model.photoCommand("preset.create", params: CreatePreset(name: self.name.trimmingCharacters(in: .whitespacesAndNewlines), group: self.presetGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "User Presets" : self.presetGroupName.trimmingCharacters(in: .whitespacesAndNewlines), groups: self.groupIDs))
            self.name = ""; try await self.refresh(); self.status = "Preset saved on this device."
        }
    }
    var validName: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 120 }
    var groupIDs: [String] { NativeSettingsGroup.allCases.filter { groups.contains($0) }.map(\.rawValue) }
    nonisolated struct PresetGroup: Identifiable {
        let name: String
        let items: [Preset]
        var id: String { name }
    }
    var presetGroups: [PresetGroup] {
        let visible = presets.filter {
            (!favoritesOnly || $0.favorite) && (query.isEmpty || ($0.name + " " + $0.group).localizedCaseInsensitiveContains(query))
        }
        let groups = Dictionary(grouping: visible, by: \.group)
        return groups.keys.sorted().map { PresetGroup(name: $0, items: groups[$0] ?? []) }
    }
    func managePreset(_ preset: Preset, command: String, value: String? = nil) async {
        guard !preset.builtin, ["preset.delete", "preset.update", "preset.rename", "preset.move"].contains(command) else { return }
        var params = ["id": preset.id]
        if let value {
            let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 120 else { error = "Enter a name up to 120 characters."; return }
            params[command == "preset.move" ? "group" : "name"] = text
        }
        let request = params
        await run { _ = try await self.model.photoCommand(command, params: request); try await self.refresh() }
    }
    func favorite(_ preset: Preset) async {
        await run { _ = try await self.model.photoCommand("preset.favorite", params: Favorite(id: preset.id, favorite: !preset.favorite)); try await self.refresh() }
    }
    func applyPreset(_ preset: Preset, batch: Bool = false) async {
        guard amount.isFinite, (0...200).contains(amount) else { return }
        await run {
            if batch {
                let ids = self.selected.sorted()
                guard !ids.isEmpty else { throw EngineError.engine("Choose other imported photos first") }
                self.beforeBatch = try await self.capture(ids)
                self.afterBatch = []; self.canRedoBatch = false
                _ = try await self.model.photoCommand("preset.apply", params: ApplyPreset(id: preset.id, amount: self.amount, ids: ids))
                self.canUndoBatch = true
                self.afterBatch = try await self.capture(ids)
                self.status = "Applied to \(ids.count) imported photos. Originals and Photos assets are unchanged."
            } else {
                guard let photo = self.model.openPhoto else { return }
                let current = try await self.model.photoCommand("develop.get", params: [String: String]())
                if self.appliedPresetID != nil, self.presetPhoto == photo,
                   current == self.presetExpectedSettings, let baseline = self.presetBaseline {
                    if self.appliedPresetID == preset.id && self.amount == self.appliedPresetAmount { return }
                    self.presetExpectedSettings = try await self.model.replacePreset(preset.id, amount: self.amount, baseline: baseline, expected: current, photo: photo)
                } else {
                    guard current.utf8.count <= 16 * 1024 * 1024 else { throw EngineError.engine("Preset baseline exceeds the editing limit") }
                    _ = try await self.model.performPhotoEdit("preset.apply", params: ApplyPreset(id: preset.id, amount: self.amount, ids: [photo.rawValue]))
                    self.presetBaseline = current
                    self.presetPhoto = photo
                    self.presetExpectedSettings = try await self.model.photoCommand("develop.get", params: [String: String]())
                }
                self.appliedPresetID = preset.id
                self.appliedPresetAmount = self.amount
                self.cachePresetSelection()
            }
            try await self.refresh()
        }
    }
    func updatePresetAmount() async {
        guard amount.isFinite, (0...200).contains(amount), let preset = appliedPresetID,
              let baseline = presetBaseline, let expected = presetExpectedSettings, let photo = presetPhoto else { return }
        let value = amount
        guard value != appliedPresetAmount else { return }
        await run {
            self.presetExpectedSettings = try await self.model.replacePreset(preset, amount: value, baseline: baseline, expected: expected, photo: photo)
            self.appliedPresetAmount = value
            self.cachePresetSelection()
            try await self.refresh()
        }
    }
    func resetPreset() async {
        guard let baseline = presetBaseline, let expected = presetExpectedSettings, let photo = presetPhoto else { return }
        await run {
            _ = try await self.model.replacePreset(nil, amount: 100, baseline: baseline, expected: expected, photo: photo)
            self.clearPresetSelection()
            self.status = "Preset reset. Earlier edits retained."
            try await self.refresh()
        }
    }
    private func cachePresetSelection() {
        guard let photo = presetPhoto, let id = appliedPresetID,
              let baseline = presetBaseline, let expected = presetExpectedSettings else { return }
        model.presetReplacementState = PresetReplacementState(photo: photo, presetID: id, baseline: baseline, expected: expected, amount: appliedPresetAmount)
    }
    private func clearPresetSelection() {
        if model.presetReplacementState?.photo == presetPhoto { model.presetReplacementState = nil }
        appliedPresetID = nil; presetBaseline = nil; presetExpectedSettings = nil; presetPhoto = nil; amount = 100; appliedPresetAmount = 100
    }
    func copySettings() async {
        guard !groups.isEmpty else { return }
        await run { _ = try await self.model.photoCommand("develop.copy", params: CopyPaste(groups: self.groupIDs)); self.status = "Selected settings copied within iLightCraft." }
    }
    func pasteSettings(batch: Bool) async {
        guard !groups.isEmpty else { return }
        await run {
            if batch {
                let ids = self.selected.sorted(); guard !ids.isEmpty else { throw EngineError.engine("Choose other photos first") }
                self.beforeBatch = try await self.capture(ids); self.afterBatch = []; self.canRedoBatch = false
                _ = try await self.model.photoCommand("develop.paste", params: CopyPaste(groups: self.groupIDs, ids: ids))
                self.canUndoBatch = true; self.afterBatch = try await self.capture(ids)
                self.status = "Pasted to \(ids.count) imported photos. Batch undo is available in this panel."
            } else {
                guard let id = self.model.openPhoto?.rawValue else { return }
                _ = try await self.model.performPhotoEdit("develop.paste", params: CopyPaste(groups: self.groupIDs, ids: [id]))
            }
            try await self.refresh()
        }
    }
    private func capture(_ ids: [UInt64]) async throws -> [Snapshot] {
        guard ids.count <= 20 else { throw EngineError.engine("Batch limit is 20 photos") }
        var rows: [Snapshot] = []; var bytes = 0
        for id in ids {
            let text = try await model.photoCommand("develop.get", params: ["id": id])
            bytes += text.utf8.count
            guard bytes <= 32 * 1024 * 1024 else { throw EngineError.engine("Batch settings exceed 32 MiB") }
            rows.append(Snapshot(id: id, settingsJSON: text))
        }
        return rows
    }
    func undoBatch(redo: Bool = false) async {
        let rows = redo ? afterBatch : beforeBatch
        guard !rows.isEmpty, redo ? canRedoBatch : canUndoBatch else { return }
        await run {
            _ = try await self.model.photoCommand("develop.restoreBatch", params: Restore(rows: rows))
            self.canUndoBatch = redo; self.canRedoBatch = !redo && !self.afterBatch.isEmpty
            self.status = redo ? "Other-photo batch restored." : "Other-photo batch undone."
        }
    }
    func importPreset(_ url: URL) async {
        await run {
            let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard url.pathExtension.lowercased() == "lcpreset", size > 0, size <= 16 * 1024 * 1024 else {
                throw EngineError.engine("Choose an iLightCraft .lcpreset file up to 16 MiB")
            }
            let result = try await self.model.photoCommand("preset.import", params: ["paths": [url.path]])
            guard let report = try JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any] else { throw EngineError.engine("Cannot read import report") }
            let imported = (report["imported"] as? [Any])?.count ?? 0
            let failed = (report["failed"] as? [Any])?.count ?? 0
            self.status = "Imported \(imported) presets; \(failed) failed."
            try await self.refresh()
        }
    }
    func exportPresets() async {
        await run {
            let url = URL.temporaryDirectory.appending(path: "iLightCraft-Presets-\(UUID()).lcpreset")
            _ = try await self.model.photoCommand("preset.export", params: Export(path: url.path))
            self.exportedFile = url; self.status = "Preset file ready to save or share."
        }
    }
    nonisolated struct InspectedVersions: Decodable { let versions: [History.Version] }
    func createVersion() async {
        await run {
            let params = self.validName ? ["name": self.name] : [String: String]()
            _ = try await self.model.photoCommand("version.create", params: params)
            self.name = ""; try await self.refresh()
        }
    }
    func updateVersion(_ index: Int) async {
        guard versions.indices.contains(index) else { return }
        await run { _ = try await self.model.photoCommand("version.update", params: ["index": index]); try await self.refresh() }
    }
    nonisolated struct BeforeRequest: Encodable, Sendable { let source: String; var index: Int?; var name: String? }
    func setBefore(version: Int? = nil, history: Int? = nil) async {
        if let version, !versions.indices.contains(version) { return }
        if let history, !self.history.indices.contains(history) { return }
        let request = BeforeRequest(source: version == nil ? "history" : "version", index: history, name: version.map { versions[$0].name })
        await run { _ = try await self.model.photoCommand("beforeAfter.setBefore", params: request) }
    }
    func clearHistory() async {
        await run { _ = try await self.model.photoCommand("history.clear", params: [String: String]()); try await self.refresh() }
    }
    func versionFromHistory(_ index: Int) async {
        guard history.indices.contains(index) else { return }
        await run {
            let label = self.history[index]
            _ = try await self.model.performPhotoEdit("history.restore", params: ["index": index])
            _ = try await self.model.photoCommand("version.create", params: ["name": label])
            try await self.refresh()
        }
    }
    func restoreVersion(_ index: Int) async {
        guard versions.indices.contains(index) else { return }
        await run { _ = try await self.model.performPhotoEdit("version.restore", params: ["index": index]); try await self.refresh() }
    }
    func renameVersion(_ index: Int) async {
        guard versions.indices.contains(index), validName else { return }
        await run { _ = try await self.model.photoCommand("version.rename", params: RenameVersion(index: index, name: self.name)); self.name = ""; try await self.refresh() }
    }
    func deleteVersion(_ index: Int) async {
        guard versions.indices.contains(index) else { return }
        await run { _ = try await self.model.photoCommand("version.delete", params: ["index": index]); try await self.refresh() }
    }
    func restoreHistory(_ index: Int) async {
        guard history.indices.contains(index) else { return }
        await run { _ = try await self.model.performPhotoEdit("history.restore", params: ["index": index]); try await self.refresh() }
    }
    func reference(version: Int? = nil, photo: Photo? = nil) async {
        await run {
            if let version, !self.versions.indices.contains(version) { return }
            let url = URL.temporaryDirectory.appending(path: "reference-\(UUID()).png")
            defer { try? FileManager.default.removeItem(at: url) }
            let command = version == nil ? "ilightcraft.export" : "ilightcraft.versionPreview"
            _ = try await self.model.photoCommand(command, params: Preview(path: url.path, id: photo?.id, index: version))
            let bytes = try await Task.detached { try Data(contentsOf: url) }.value
            guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read reference preview") }
            self.referenceImage = image
            self.referenceName = photo?.name ?? version.flatMap { self.versions.dropFirst($0).first?.name } ?? "Reference"
        }
    }
    func clearReference() { referenceImage = nil; referenceName = "" }
    func virtualCopy() async {
        guard name.count <= 120 else { error = "Use a name of up to 120 characters"; return }
        await run {
            guard let id = self.model.openPhoto?.rawValue else { return }
            let text = try await self.model.photoCommand("photo.inspect", params: ["id": id])
            let source = try JSONDecoder().decode(ComputationalToolsSession<Engine, Importer>.CatalogSource.self, from: Data(text.utf8)).source
            guard source.type == "file", let path = source.path else { throw EngineError.engine("This photo has no local source") }
            let result = try await self.model.photoCommand("photo.virtualCopy", params: CopyRequest(ids: [id], name: self.name.isEmpty ? "Alternate Edit" : self.name))
            guard let copy = try JSONDecoder().decode(MadeCopies.self, from: Data(result.utf8)).ids.first else { throw EngineError.engine("The copy was not created") }
            await self.onOpen(PhotoID(rawValue: copy), URL(filePath: path))
        }
    }
    func undo(redo: Bool = false) async {
        await run {
            if redo { await self.model.redo() } else { await self.model.undo() }
            self.clearPresetSelection()
            try await self.refresh()
        }
    }
    private func run(_ action: @escaping @MainActor () async throws -> Void) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do { try await action() } catch { self.error = error.localizedDescription }
    }
}
