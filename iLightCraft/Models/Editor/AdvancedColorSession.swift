import Foundation
import Observation
import UIKit

nonisolated struct NativeDevelopControl: Decodable, Identifiable, Sendable {
    let id: String
    let label: String
    let min: Double
    let max: Double
    let step: Double
    let value: Double
    let defaultValue: Double
    enum CodingKeys: String, CodingKey { case id, label, min, max, step, value; case defaultValue = "default" }
    var isValid: Bool {
        [min, max, step, value, defaultValue].allSatisfy(\.isFinite) && min < max && step > 0
            && (min...max).contains(value) && (min...max).contains(defaultValue)
    }
}

@Observable
@MainActor
final class AdvancedColorSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    let pointColor: Bool
    let optics: Bool
    var lensProfile = false
    var removeCA = false
    var constrainCrop = true
    private(set) var embeddedLens = false
    private(set) var upright = "off"
    var guiding = false
    var guideLines: [[CGPoint]] = []
    var guideStroke: [CGPoint] = []
    private(set) var controls: [NativeDevelopControl] = []
    var values: [String: Double] = [:]
    private(set) var sampleCount = 0
    var selectedSample = 0
    var picking = false
    private(set) var image: UIImage?
    private(set) var loaded = false
    private(set) var busy = false
    var error: String?
    nonisolated struct Settings: Decodable {
        let point_colors: [Sample]
        struct Sample: Decodable { let lum: Double; let chroma: Double; let hue: Double }
    }
    nonisolated struct Pick: Encodable, Sendable {
        let x: Double; let y: Double
        let space = "uncroppedPreview"
    }
    nonisolated struct Values: Encodable, Sendable { let values: [String: Double] }
    nonisolated struct OpticalSettings: Decodable {
        let optics: Options
        let geometry: Geometry
        struct Options: Decodable { let lens_profile: Bool; let remove_ca: Bool }
        struct Geometry: Decodable { let constrain_crop: Bool; let upright: String }
    }
    nonisolated struct Inspect: Decodable {
        let embedded_lens: Lens?
        struct Lens: Decodable {
            let warp: Warp?
            let vignette: Vignette?
            struct Warp: Decodable { let planes: [[Double]] }
            struct Vignette: Decodable { let k: [Double] }
        }
    }
    nonisolated struct OptionsRequest: Encodable, Sendable { let settings: [String: [String: Bool]] }
    nonisolated struct Preview: Encodable, Sendable { let path: String; let neutralPerspective: Bool }
    nonisolated struct Guides: Encodable, Sendable { let guides: [[Double]] }
    init(model: EditorViewModel<Engine, Importer>, pointColor: Bool, optics: Bool = false) {
        self.model = model; self.pointColor = pointColor; self.optics = optics
    }
    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await read(); try await refreshImage(); loaded = true }
        catch { self.error = error.localizedDescription }
    }
    private func read() async throws {
        let text = try await model.photoCommand("develop.controls", params: [String: String]())
        let controls = try JSONDecoder().decode([NativeDevelopControl].self, from: Data(text.utf8))
        guard controls.count <= 4096, controls.allSatisfy(\.isValid) else { throw EngineError.engine("Invalid develop control list") }
        self.controls = controls.filter { optics ? ($0.id.hasPrefix("optics.") || $0.id.hasPrefix("geometry.")) : $0.id.hasPrefix(pointColor ? "pointColor." : "grading.") }
        values = Dictionary(self.controls.map { ($0.id, $0.value) }, uniquingKeysWith: { _, new in new })
        if optics {
            let text = try await model.photoCommand("develop.get", params: [String: String]())
            let value = try JSONDecoder().decode(OpticalSettings.self, from: Data(text.utf8))
            lensProfile = value.optics.lens_profile; removeCA = value.optics.remove_ca
            constrainCrop = value.geometry.constrain_crop; upright = value.geometry.upright
            let info = try await model.photoCommand("photo.inspect", params: [String: String]())
            let lens = try JSONDecoder().decode(Inspect.self, from: Data(info.utf8)).embedded_lens
            embeddedLens = lens?.warp != nil || lens?.vignette != nil
        }
        if pointColor {
            let text = try await model.photoCommand("develop.get", params: [String: String]())
            let settings = try JSONDecoder().decode(Settings.self, from: Data(text.utf8))
            guard settings.point_colors.count <= 8,
                  settings.point_colors.allSatisfy({ [$0.lum, $0.chroma, $0.hue].allSatisfy(\.isFinite) }) else {
                throw EngineError.engine("Invalid Point Color samples")
            }
            sampleCount = settings.point_colors.count
            selectedSample = min(selectedSample, max(0, sampleCount - 1))
        }
    }
    func matching(_ prefix: String) -> [NativeDevelopControl] { controls.filter { $0.id.hasPrefix(prefix) } }
    func setDraft(_ id: String, _ value: Double) {
        guard !busy, value.isFinite, let spec = controls.first(where: { $0.id == id }) else { return }
        values[id] = min(spec.max, max(spec.min, value))
    }
    func apply(_ ids: [String]) async {
        guard loaded, !busy else { return }
        var patch: [String: Double] = [:]
        for id in ids {
            guard let spec = controls.first(where: { $0.id == id }), let value = values[id], value.isFinite,
                  (spec.min...spec.max).contains(value) else { error = "Choose a valid color adjustment."; return }
            if value != spec.value { patch[id] = value }
        }
        guard !patch.isEmpty else { return }
        await mutate("develop.set", params: Values(values: patch))
    }
    func reset(_ prefix: String) async {
        guard loaded, !busy else { return }
        let list = matching(prefix)
        for control in list { values[control.id] = control.defaultValue }
        await apply(list.map(\.id))
    }
    func pick(_ point: CGPoint) async {
        guard pointColor, picking, sampleCount < 8, !busy, point.x.isFinite, point.y.isFinite else { return }
        picking = false
        selectedSample = sampleCount
        await mutate("pointColor.pick", params: Pick(x: Double(min(1, max(0, point.x))), y: Double(min(1, max(0, point.y)))))
    }
    func deleteSample() async {
        guard sampleCount > 0, (0..<sampleCount).contains(selectedSample) else { return }
        picking = false
        await mutate("pointColor.delete", params: ["index": selectedSample])
    }
    func option(_ section: String, _ key: String, _ value: Bool) async {
        await mutate("develop.merge", params: OptionsRequest(settings: [section: [key: value]]))
    }
    func setUpright(_ mode: String) async {
        guard ["off", "auto", "level", "vertical", "full"].contains(mode) else { return }
        guiding = false
        await mutate("geometry.upright", params: ["mode": mode])
    }
    func beginGuides() async {
        guard !busy else { return }
        guiding = true; guideLines = []; guideStroke = []
        busy = true; defer { busy = false }
        do { try await refreshImage() } catch { self.error = error.localizedDescription; guiding = false }
    }
    func finishGuide() {
        guard guideLines.count < 4, guideStroke.count == 2, let a = guideStroke.first, let b = guideStroke.last,
              hypot(a.x - b.x, a.y - b.y) > 0.02 else { guideStroke = []; return }
        guideLines.append([a, b]); guideStroke = []
    }
    func applyGuides() async {
        guard (2...4).contains(guideLines.count) else { error = "Draw two to four guides on the main photo."; return }
        let guides = guideLines.compactMap { line -> [Double]? in
            guard let a = line.first, let b = line.last else { return nil }
            return [Double(a.x), Double(a.y), Double(b.x), Double(b.y)]
        }
        guiding = false
        await mutate("geometry.guides", params: Guides(guides: guides))
    }
    func mutate(_ command: String, params: some Encodable & Sendable) async {
        guard loaded, !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await model.performPhotoEdit(command, params: params)
            try await read(); try await refreshImage()
        } catch { self.error = error.localizedDescription; try? await read() }
    }
    func undo(redo: Bool = false) async {
        guard !busy else { return }
        busy = true; picking = false; error = nil; defer { busy = false }
        if redo { await model.redo() } else { await model.undo() }
        do { try await read(); try await refreshImage() } catch { self.error = error.localizedDescription }
    }
    private func refreshImage() async throws {
        guard pointColor || (optics && guiding) else { return }
        let url = URL.temporaryDirectory.appending(path: "point-color-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await model.photoCommand("ilightcraft.cropPreview", params: Preview(path: url.path, neutralPerspective: optics))
        let bytes = try await Task.detached { try Data(contentsOf: url) }.value
        guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read Point Color preview") }
        self.image = image
    }
}
