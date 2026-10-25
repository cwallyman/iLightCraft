import Foundation
import Observation
import UIKit

@Observable
@MainActor
final class ToneCurveSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    var channel: ToneCurveChannel = .master
    var curves: [ToneCurveChannel: ToneCurvePoints] = [:]
    var selectedPoint: Int?
    private(set) var busy = false
    private(set) var loaded = false
    private(set) var image: UIImage?
    var error: String?
    private var saved: [ToneCurveChannel: ToneCurvePoints] = [:]

    nonisolated struct Settings: Decodable {
        let curve: Channels
        struct Channels: Decodable {
            let master: [ToneCurvePoints.Point]
            let red: [ToneCurvePoints.Point]
            let green: [ToneCurvePoints.Point]
            let blue: [ToneCurvePoints.Point]
        }
    }
    nonisolated struct SetRequest: Encodable, Sendable {
        let channel: String
        let points: [[Double]]
    }
    nonisolated struct PreviewRequest: Encodable, Sendable {
        let path: String
        let format = "png"
        let longEdge = 1200
        let metadata = "none"
        let colorSpace = "srgb"
    }

    init(model: EditorViewModel<Engine, Importer>) { self.model = model }
    var points: [ToneCurvePoints.Point] { curves[channel]?.points ?? ToneCurvePoints.identity }
    var selected: ToneCurvePoints.Point? {
        guard let index = selectedPoint, points.indices.contains(index) else { return nil }
        return points[index]
    }

    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await readSettings(); loaded = true; try await refreshImage() }
        catch { self.error = Self.message(error) }
    }

    private func readSettings() async throws {
        let text = try await model.photoCommand("develop.get", params: [String: String]())
        let c = try JSONDecoder().decode(Settings.self, from: Data(text.utf8)).curve
        curves = [.master: try ToneCurvePoints(c.master), .red: try ToneCurvePoints(c.red),
                  .green: try ToneCurvePoints(c.green), .blue: try ToneCurvePoints(c.blue)]
        saved = curves
        if let selectedPoint, !points.indices.contains(selectedPoint) { self.selectedPoint = nil }
    }

    func begin(x: Double, y: Double, width: Double, height: Double) {
        guard !busy, loaded, width > 0, height > 0 else { return }
        let nearest = points.indices.min { a, b in
            hypot((points[a].x - x) * width, (points[a].y - y) * height)
                < hypot((points[b].x - x) * width, (points[b].y - y) * height)
        }
        if let nearest, hypot((points[nearest].x - x) * width, (points[nearest].y - y) * height) <= 24 {
            selectedPoint = nearest
        } else {
            selectedPoint = curves[channel]?.insert(x: x, y: y)
        }
    }
    func move(x: Double, y: Double) {
        guard !busy, let index = selectedPoint else { return }
        curves[channel]?.move(index, x: x, y: y)
    }
    func addPoint() async {
        guard !busy, loaded else { return }
        let p = points
        guard let gap = p.indices.dropLast().max(by: { p[$0 + 1].x - p[$0].x < p[$1 + 1].x - p[$1].x }),
              let curve = curves[channel] else { return }
        let x = (p[gap].x + p[gap + 1].x) / 2
        selectedPoint = curves[channel]?.insert(x: x, y: curve.value(at: x))
        await commit()
    }
    func deletePoint() async {
        guard !busy, let index = selectedPoint else { return }
        curves[channel]?.remove(index)
        selectedPoint = nil
        await commit()
    }
    func commit() async {
        guard !busy, let curve = curves[channel], curve != saved[channel] else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await model.performPhotoEdit("develop.curve", params: SetRequest(channel: channel.rawValue, points: curve.points.map { [$0.x, $0.y] }))
            try await readSettings()
            try await refreshImage()
        } catch {
            self.error = Self.message(error)
            // Recover actual saved values, including the case where rendering failed after the edit.
            try? await readSettings()
        }
    }
    func reset(all: Bool) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await model.performPhotoEdit("curve.reset", params: ["channel": all ? "point" : channel.rawValue])
            selectedPoint = nil; try await readSettings(); loaded = true; try await refreshImage()
        } catch { self.error = Self.message(error) }
    }
    func undo(redo: Bool = false) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        if redo { await model.redo() } else { await model.undo() }
        do { selectedPoint = nil; try await readSettings(); try await refreshImage() }
        catch { self.error = Self.message(error) }
    }
    private func refreshImage() async throws {
        let url = URL.temporaryDirectory.appending(path: "tone-curve-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        _ = try await model.photoCommand("ilightcraft.export", params: PreviewRequest(path: url.path))
        let bytes = try await Task.detached { try Data(contentsOf: url) }.value
        guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read the tone curve preview") }
        self.image = image
    }
    private static func message(_ error: Error) -> String { (error as? EngineError)?.message ?? error.localizedDescription }
}
