import Foundation
import Testing
@testable import iLightCraft

/// Saved regression coverage. Not run automatically during device installation.
@Suite(.serialized)
@MainActor
struct RemainingFeaturesTests {
    @Test func advancedUndoKeepsExtraFieldsWithoutOverwritingBasicSliders() throws {
        let text = #"{"detail":{"sharpen_amount":30,"radius":1.4},"grain":{"amount":12,"size":55},"hdr":{"enabled":true,"headroom":3},"grading":{"balance":24},"point_colors":[]}"#
        let result = try EngineManager.nativeUndoSettings(from: text)
        let value = try #require(JSONSerialization.jsonObject(with: Data(result.utf8)) as? [String: Any])
        let detail = try #require(value["detail"] as? [String: Any])
        #expect(detail["sharpen_amount"] == nil)
        #expect(detail["radius"] as? Double == 1.4)
        #expect((value["grain"] as? [String: Any])?["amount"] == nil)
        #expect((value["grain"] as? [String: Any])?["size"] as? Int == 55)
        #expect((value["hdr"] as? [String: Any])?["enabled"] == nil)
        #expect(value["grading"] != nil && value["point_colors"] != nil)
    }
    @Test func developControlRejectsInvalidRanges() throws {
        let valid = #"{"id":"grading.balance","label":"Balance","min":-100,"max":100,"step":1,"value":0,"default":0}"#
        #expect(try JSONDecoder().decode(NativeDevelopControl.self, from: Data(valid.utf8)).isValid)
        let invalid = valid.replacingOccurrences(of: "\"max\":100", with: "\"max\":-100")
        #expect(try !JSONDecoder().decode(NativeDevelopControl.self, from: Data(invalid.utf8)).isValid)
    }
    @Test func resetMaskColorPreservesToneAndDetail() {
        var values = MaskColorAdjustments()
        values.exposure = 0.7; values.contrast = 20; values.texture = 30; values.noise = 45
        values.colorize(hue: 240); values.resetColor()
        #expect(values.exposure == 0.7 && values.contrast == 20 && values.texture == 30 && values.noise == 45)
        #expect(values.colorAmount == 0 && values.saturation == 0)
    }
    @Test func backupRejectsTraversalAndDetectsTamperedMedia() throws {
        for path in ["", "/absolute", "../escape", "Engine/../escape", "Engine//file", "Engine/./file", "Engine\\file"] {
            #expect(!NativeLibraryBackup.safeRelative(path))
        }
        #expect(NativeLibraryBackup.safeRelative("Engine/catalog.snap"))
        let base = URL.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let root = base.appending(path: "library")
        let destination = base.appending(path: "backups")
        try FileManager.default.createDirectory(at: root.appending(path: "Engine"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let snapshot = #"{"format":"lightcraft-catalog","version":1,"seq":0,"catalog":{"photos":{}}}"#
        try Data(snapshot.utf8).write(to: root.appending(path: "Engine/catalog.snap"))
        let package = try NativeLibraryBackup.create(root: root, destination: destination, progress: { _ in })
        try Data("tampered".utf8).write(to: package.appending(path: "Engine/catalog.snap"))
        #expect(throws: (any Error).self) { try NativeLibraryBackup.restore(package: package, progress: { _ in }) }
    }
    @Test func manualMaskFailureIsAtomicAndBrushIsOneUndoStep() async throws {
        let support = EngineManagerTests()
        let manager = try support.makeManager(maxPixels: 128)
        let fixture = try support.fixtureURL()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let model = EditorViewModel(engine: manager, importer: FakeImporter(), previewPixels: 96)
        #expect(await model.open(pickedURL: fixture))
        let before = try await model.photoCommand("develop.get", params: [String: String]())
        do {
            _ = try await model.photoCommand("ilightcraft.manualMask", params: ["kind": "colorRange", "operation": "new"])
            Issue.record("A color-range mask without a sample must fail")
        } catch { }
        let failed = try await model.photoCommand("develop.get", params: [String: String]())
        #expect(before == failed)
        struct Brush: Encodable, Sendable {
            let kind = "brush"; let operation = "new"
            let points = [[0.2, 0.2], [0.5, 0.5]]
            let size = 0.05; let flow = 100; let density = 100; let feather = 50
        }
        _ = try await model.performPhotoEdit("ilightcraft.manualMask", params: Brush())
        let after = try await model.photoCommand("develop.get", params: [String: String]())
        #expect(after != before)
        await model.undo()
        let undone = try await model.photoCommand("develop.get", params: [String: String]())
        #expect(undone == before)
        await model.redo()
        let redone = try await model.photoCommand("develop.get", params: [String: String]())
        #expect(redone == after)
    }
    @Test func invalidBatchRowDoesNotChangeTheValidPhoto() async throws {
        let support = EngineManagerTests()
        let manager = try support.makeManager(maxPixels: 128)
        let fixture = try support.fixtureURL()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let model = EditorViewModel(engine: manager, importer: FakeImporter(), previewPixels: 96)
        #expect(await model.open(pickedURL: fixture))
        let id = try #require(model.openPhoto?.rawValue)
        let before = try await model.photoCommand("develop.get", params: [String: String]())
        struct Row: Encodable, Sendable { let id: UInt64; let settingsJSON: String }
        struct Restore: Encodable, Sendable { let rows: [Row] }
        let rows = [Row(id: id, settingsJSON: #"{"light":{"exposure":2}}"#), Row(id: UInt64.max, settingsJSON: "{}")]
        do {
            _ = try await model.photoCommand("develop.restoreBatch", params: Restore(rows: rows))
            Issue.record("A missing photo must reject the entire batch")
        } catch { }
        let after = try await model.photoCommand("develop.get", params: [String: String]())
        #expect(after == before)
    }

}
