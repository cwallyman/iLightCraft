import Foundation
import Testing
import UIKit
@testable import iLightCraft

/// Saved for user execution. No simulator or automated test run accompanies this change.
@Suite(.serialized)
@MainActor
struct BeforeEditedComparisonTests {
    nonisolated private struct Preview: Encodable, Sendable {
        let id: UInt64
        let path: String
        let before: Bool
        let longEdge: Int
    }

    @Test func comparisonRendersBothStatesWithoutChangingEdits() async throws {
        let directory = URL.temporaryDirectory.appending(path: "before-edited-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "source.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 32)).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        }
        try #require(image.pngData()).write(to: source)
        let engine = try EngineManager(dataDirectory: directory.appending(path: "Library"), maxPixels: 128)
        let model = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 128)
        await model.open(pickedURL: source)
        let photo = try #require(model.openPhoto)
        _ = try await model.performPhotoEdit("develop.set", params: ["values": ["light.exposure": 1.0]])
        let settings = try await model.photoCommand("develop.get", params: [String: String]())
        let before = directory.appending(path: "before.png")
        let edited = directory.appending(path: "edited.png")
        _ = try await model.photoCommand("ilightcraft.comparisonPreview", params: Preview(id: photo.rawValue, path: before.path, before: true, longEdge: 256))
        _ = try await model.photoCommand("ilightcraft.comparisonPreview", params: Preview(id: photo.rawValue, path: edited.path, before: false, longEdge: 256))
        let beforeBytes = try Data(contentsOf: before)
        let editedBytes = try Data(contentsOf: edited)
        #expect(beforeBytes != editedBytes)
        let beforeImage = try #require(UIImage(data: beforeBytes))
        let editedImage = try #require(UIImage(data: editedBytes))
        #expect(beforeImage.size == editedImage.size)
        #expect(max(editedImage.size.width, editedImage.size.height) <= 256)
        let afterSettings = try await model.photoCommand("develop.get", params: [String: String]())
        #expect(settings == afterSettings)
        #expect(model.openPhoto == photo)
    }
}
