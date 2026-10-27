//
//  EditorAuxiliarySession.swift
//  iLightCraft
//

import Foundation
import Observation
import UIKit

/// NativeKeywordInput bounds keyword edits before they reach the catalog.
nonisolated enum NativeKeywordInput {
    static func clean(_ text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 256, !value.contains(where: { $0.isNewline }) else { return nil }
        return value
    }
}

/// NativeEyeRequest uses the uncropped, oriented photo's normalized coordinates.
nonisolated struct NativeEyeRequest: Encodable, Sendable {
    let center: [Double]
    let rx: Double
    let ry: Double
    let pupilSize: Double
    let darken: Double
    let pet: Bool
    init?(center: CGPoint, radius: Double, pupilSize: Double, darken: Double, pet: Bool) {
        let values = [Double(center.x), Double(center.y), radius, pupilSize, darken]
        guard values.allSatisfy(\.isFinite), (0...1).contains(center.x), (0...1).contains(center.y),
              (0.002...0.1).contains(radius), (0...100).contains(pupilSize), (0...100).contains(darken) else { return nil }
        self.center = [Double(center.x), Double(center.y)]
        rx = radius; ry = radius
        self.pupilSize = pupilSize; self.darken = darken; self.pet = pet
    }
}

/// EditorAuxiliarySession connects Keywords and Red Eye to existing engine commands.
@Observable @MainActor
final class EditorAuxiliarySession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    enum Mode { case keywords, redEye, whiteBalance }
    let model: EditorViewModel<Engine, Importer>
    let mode: Mode
    var keyword = ""
    private(set) var keywords: [String] = []
    var center: CGPoint?
    var keywordView = "keywords"
    var setName = ""
    private(set) var suggestions: [String] = []
    private(set) var keywordSets: [String] = []
    private(set) var currentSet = "Recent Keywords"
    private(set) var setKeywords: [String] = []
    private(set) var keywordList: [(String, Int)] = []
    var picking = true
    var radius = 0.02
    var pupilSize = 50.0
    var darken = 50.0
    var pet = false
    private(set) var image: UIImage?
    private(set) var eyes: [Eye] = []
    private(set) var loaded = false
    private(set) var busy = false
    var error: String?
    nonisolated struct Eye: Decodable {
        let pet: Bool
        let pupil_size: Double
        let darken: Double
        let catchlight: Point?
        struct Point: Decodable { let x: Double; let y: Double }
    }
    nonisolated struct Sets: Decodable {
        let sets: [Entry]; let current: String; let keywords: [String]
        struct Entry: Decodable { let name: String }
    }
    nonisolated struct Suggest: Encodable, Sendable { let prefix: String; let limit = 12 }
    nonisolated struct SaveSet: Encodable, Sendable { let name: String; let keywords: [String] }
    nonisolated struct Settings: Decodable { let red_eye: [Eye] }
    nonisolated struct Photo: Decodable {
        let meta: Metadata
        struct Metadata: Decodable { let keywords: [String] }
    }
    nonisolated struct Preview: Encodable, Sendable { let path: String; let neutralPerspective = true }
    nonisolated struct KeywordAdd: Encodable, Sendable { let addKeywords: [String] }
    nonisolated struct KeywordRemove: Encodable, Sendable { let removeKeywords: [String] }

    init(model: EditorViewModel<Engine, Importer>, mode: Mode) { self.model = model; self.mode = mode }

    func load() async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do { try await read(); loaded = true }
        catch { self.error = error.localizedDescription }
    }

    private func read() async throws {
        if mode == .keywords {
            let json = try await model.photoCommand("photo.inspect", params: [String: String]())
            let photo = try JSONDecoder().decode(Photo.self, from: Data(json.utf8))
            guard photo.meta.keywords.count <= 4096 else { throw EngineError.engine("Too many keywords to display") }
            keywords = photo.meta.keywords
            let sets = try await model.photoCommand("keyword.sets", params: [String: String]())
            let set = try JSONDecoder().decode(Sets.self, from: Data(sets.utf8))
            guard set.sets.count <= 1000, set.keywords.count <= 9 else { throw EngineError.engine("Too many keyword sets") }
            keywordSets = set.sets.map(\.name); currentSet = set.current; setKeywords = set.keywords
            let tree = try await model.photoCommand("keyword.list", params: [String: String]())
            guard tree.utf8.count <= 16 * 1024 * 1024, let nodes = try JSONSerialization.jsonObject(with: Data(tree.utf8)) as? [[String: Any]] else {
                throw EngineError.engine("Invalid keyword tree")
            }
            var pending = nodes.reversed().map { ($0, 0) }
            var rows: [(String, Int)] = []
            while let (node, depth) = pending.popLast() {
                guard depth <= 32, rows.count < 8192 else { throw EngineError.engine("Keyword tree exceeds display limits") }
                if let path = node["path"] as? String { rows.append((path, node["count"] as? Int ?? 0)) }
                if let children = node["children"] as? [[String: Any]] { pending += children.reversed().map { ($0, depth + 1) } }
            }
            keywordList = rows
        } else {
            if mode == .redEye {
            let json = try await model.photoCommand("develop.get", params: [String: String]())
            let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
            guard settings.red_eye.count <= 256 else { throw EngineError.engine("Too many eye corrections to display") }
            eyes = settings.red_eye
            }
            let file = URL.temporaryDirectory.appending(path: "red-eye-\(UUID()).png")
            defer { try? FileManager.default.removeItem(at: file) }
            _ = try await model.photoCommand("ilightcraft.cropPreview", params: Preview(path: file.path))
            let bytes = try await Task.detached { try Data(contentsOf: file) }.value
            guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read Red Eye preview") }
            self.image = image
        }
    }

    private func mutate(_ command: String, params: some Encodable & Sendable) async {
        guard loaded, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            if mode == .keywords {
                _ = try await model.photoCommand(command, params: params)
            } else {
                _ = try await model.performPhotoEdit(command, params: params)
            }
            try await read()
        } catch { self.error = error.localizedDescription }
    }

    var displayedKeywords: [String] {
        if keywordView == "containing" {
            return Array(Set(keywords.flatMap { $0.split(separator: "|").map(String.init) })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return keywords
    }
    func suggest() async {
        guard mode == .keywords, !busy else { return }
        let prefix = keyword
        do {
            let text = try await model.photoCommand("keyword.suggest", params: Suggest(prefix: String(prefix.prefix(256))))
            let result = try JSONDecoder().decode([String].self, from: Data(text.utf8))
            if keyword == prefix { suggestions = Array(result.prefix(12)) }
        } catch { self.error = error.localizedDescription }
    }
    func useSet(_ name: String) async { await mutate("keyword.useSet", params: ["name": name]) }
    func saveSet() async {
        guard let name = NativeKeywordInput.clean(setName), !keywords.isEmpty else { return }
        await mutate("keyword.saveSet", params: SaveSet(name: name, keywords: Array(keywords.prefix(9))))
        if error == nil { setName = "" }
    }
    func deleteSet() async {
        guard currentSet != "Recent Keywords" else { return }
        await mutate("keyword.deleteSet", params: ["name": currentSet])
    }
    func applyKeyword(_ value: String) async {
        guard NativeKeywordInput.clean(value) != nil else { return }
        await mutate("photo.setMeta", params: KeywordAdd(addKeywords: [value]))
    }
    func catchlight(_ index: Int, on: Bool) async {
        guard eyes.indices.contains(index), eyes[index].pet else { return }
        await mutate("redeye.catchlight", params: Catchlight(index: index, on: on))
    }
    nonisolated struct Catchlight: Encodable, Sendable { let index: Int; let on: Bool }
    nonisolated struct ControlValues: Encodable, Sendable { let values: [String: Double] }
    func adjustEye(_ index: Int, pupilSize: Double, darken: Double) async {
        guard eyes.indices.contains(index), [pupilSize, darken].allSatisfy(\.isFinite),
              (0...100).contains(pupilSize), (0...100).contains(darken) else { return }
        await mutate("develop.set", params: ControlValues(values: ["redEye.\(index).pupilSize": pupilSize, "redEye.\(index).darken": darken]))
    }
    func removeAllEyes() async {
        guard loaded, !busy else { return }
        busy = true; defer { busy = false }
        do {
            for index in eyes.indices.reversed() { _ = try await model.performPhotoEdit("redeye.delete", params: ["index": index]) }
            try await read()
        } catch { self.error = error.localizedDescription }
    }
    func addKeyword() async {
        guard let value = NativeKeywordInput.clean(keyword), keywords.count < 4096 else {
            error = "Enter one keyword, up to 256 characters."; return
        }
        await mutate("photo.setMeta", params: KeywordAdd(addKeywords: [value]))
        if error == nil { keyword = "" }
    }
    func removeKeyword(_ value: String) async {
        guard keywords.contains(value) else { return }
        await mutate("photo.setMeta", params: KeywordRemove(removeKeywords: [value]))
    }
    nonisolated struct WhiteBalancePick: Encodable, Sendable { let x: Double; let y: Double }
    func pickWhiteBalance(_ point: CGPoint) async {
        guard mode == .whiteBalance, point.x.isFinite, point.y.isFinite,
              (0...1).contains(point.x), (0...1).contains(point.y) else { return }
        center = point
        await mutate("develop.wbPick", params: WhiteBalancePick(x: Double(point.x), y: Double(point.y)))
    }
    func addEye() async {
        guard eyes.count < 256, let center,
              let request = NativeEyeRequest(center: center, radius: radius, pupilSize: pupilSize, darken: darken, pet: pet) else {
            error = "Select an eye on the photo first."; return
        }
        await mutate("redeye.add", params: request)
        if error == nil { self.center = nil; picking = true }
    }
    func removeEye(_ index: Int) async {
        guard eyes.indices.contains(index) else { return }
        await mutate("redeye.delete", params: ["index": index])
    }
    func undo(redo: Bool = false) async {
        guard !busy else { return }
        if redo { await model.redo() } else { await model.undo() }
        await load()
    }
}
