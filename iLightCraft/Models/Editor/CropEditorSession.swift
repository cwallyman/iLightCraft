//
//  CropEditorSession.swift
//  iLightCraft
//

import Foundation
import Observation
import UIKit

/// CropEditorSession keeps a local draft; Cancel leaves the photo's saved settings untouched.
@Observable
@MainActor
final class CropEditorSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {

    var draft: CropSettings
    var aspect = "free"
    var portrait = false
    private(set) var image: UIImage?
    private(set) var isLoading = false
    var error: String?
    private let model: EditorViewModel<Engine, Importer>

    nonisolated private struct Preview: Encodable, Sendable {

        let path: String
        let orientation: String
        let flipH: Bool
        let flipV: Bool
    }

    init(model: EditorViewModel<Engine, Importer>) {
        self.model = model
        draft = model.cropSettings
        if let pair = draft.crop.aspect, pair.count == 2 {
            aspect = "current"
        }
    }

    var ratio: CGFloat? {
        guard let pair = draft.crop.aspect, pair.count == 2, let a = pair.first, let b = pair.last,
              a > 0, b > 0 else { return nil }
        return CGFloat(a) / CGFloat(b)
    }

    /// Flips are applied after cropping by the engine, so the displayed selection mirrors its stored coordinates.
    var selection: CropSettings.Rectangle {
        get { mirrored(draft.crop.geometry.rect) }
        set { draft.crop.geometry.rect = mirrored(newValue) }
    }

    var previewAngle: Double {
        (draft.crop.flip_h != draft.crop.flip_v ? -1 : 1) * draft.crop.geometry.angle
    }

    private func mirrored(_ rectangle: CropSettings.Rectangle) -> CropSettings.Rectangle {
        var r = rectangle.cgRect
        if draft.crop.flip_h { r.origin.x = 1 - r.maxX }
        if draft.crop.flip_v { r.origin.y = 1 - r.maxY }
        return .init(r)
    }

    func loadPreview() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let url = URL.temporaryDirectory.appending(path: "crop-preview-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await model.photoCommand("ilightcraft.cropPreview", params: Preview(
                path: url.path(percentEncoded: false), orientation: draft.orientation,
                flipH: draft.crop.flip_h, flipV: draft.crop.flip_v
            ))
            let data = try await Task.detached(priority: .userInitiated) { try Data(contentsOf: url) }.value
            guard let image = UIImage(data: data) else { throw EngineError.engine("Cannot read the crop preview") }
            self.image = image
            if aspect == "free" { portrait = image.size.height > image.size.width }
        } catch {
            self.error = (error as? EngineError)?.message ?? error.localizedDescription
        }
    }

    func chooseAspect() {
        guard let image else { return }
        if aspect == "free" {
            draft.crop.aspect = nil
            return
        }
        let parts = aspect.split(separator: "x").compactMap { Double($0) }
        var ratio: Double
        if aspect == "original" {
            ratio = Double(image.size.width / image.size.height)
        } else if parts.count == 2, let a = parts.first, let b = parts.last, b > 0 {
            ratio = portrait ? min(a, b) / max(a, b) : max(a, b) / min(a, b)
        } else {
            return
        }
        ratio = min(20, max(0.05, ratio))
        let normalized = ratio * Double(image.size.height / image.size.width)
        let width = min(1, normalized)
        let height = min(1, 1 / normalized)
        draft.crop.geometry.rect = .init(CGRect(x: (1 - width) / 2, y: (1 - height) / 2,
                                               width: width, height: height))
        draft.crop.aspect = [UInt32((ratio * 10000).rounded()), 10000]
    }

    func rotate(clockwise: Bool) async {
        draft.rotate(clockwise: clockwise)
        aspect = "free"
        await loadPreview()
    }

    func flip(horizontal: Bool) async {
        if horizontal { draft.crop.flip_h.toggle() } else { draft.crop.flip_v.toggle() }
        await loadPreview()
    }

    func refreshAfterHistory() async {
        draft = model.cropSettings
        aspect = draft.crop.aspect == nil ? "free" : "current"
        await loadPreview()
    }

    func apply() async -> Bool {
        await model.applyCrop(draft)
        if let message = model.errorMessage {
            error = message
            return false
        }
        return true
    }
}
