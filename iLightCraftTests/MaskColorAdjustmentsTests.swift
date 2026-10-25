import Foundation
import Testing
@testable import iLightCraft

struct MaskColorAdjustmentsTests {
    @Test func oldExposureOnlySettingsDecodeWithNeutralColor() throws {
        let value = try JSONDecoder().decode(MaskColorAdjustments.self, from: Data(#"{"exposure":0.8}"#.utf8))
        #expect(value.exposure == 0.8 && value.temperature == 0 && value.colorAmount == 0)
    }
    @Test func colorizeAndResetRetainExposureAndIndependentMaskValues() throws {
        var subject = MaskColorAdjustments(); subject.exposure = 0.5
        subject.colorize(hue: 0)
        var background = MaskColorAdjustments(); background.colorize(hue: 240)
        #expect(subject.colorHue == 0 && background.colorHue == 240)
        #expect(subject.saturation == -100 && background.colorAmount == 100)
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(background)) as? [String: Double]
        #expect(encoded?["color_hue"] == 240 && encoded?["color_sat"] == 100)
        #expect(encoded?["temp"] == 0 && encoded?["colorAmount"] == nil)
        subject.resetColor()
        #expect(subject.exposure == 0.5 && subject.saturation == 0 && subject.colorAmount == 0)
        #expect(background.colorAmount == 100)
    }
    @Test func invalidColorInputCannotReachEngine() throws {
        var color = MaskColorAdjustments(); color.temperature = .nan
        #expect(!color.isValid)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(MaskColorAdjustments.self, from: Data(#"{"color_hue":361}"#.utf8))
        }
    }
}

@Suite(.serialized)
@MainActor
struct MaskColorBridgeTests {
    /// Saved for manual execution. Generated half-image masks need no Vision or personal media.
    @Test func twoMasksKeepIndependentColorsAcrossUndoRedo() async throws {
        typealias Session = ComputationalToolsSession<EngineManager, FakeImporter>
        let support = EngineManagerTests()
        let manager = try support.makeManager(maxPixels: 128)
        let fixture = try support.fixtureURL()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let model = EditorViewModel(engine: manager, importer: FakeImporter(), previewPixels: 96)
        #expect(await model.open(pickedURL: fixture))
        let left = (0..<256).map { UInt8($0 % 16 < 8 ? 255 : 0) }
        let right = left.map { UInt8(255 - Int($0)) }
        let decoder = JSONDecoder()
        let a = try await model.performPhotoEdit("ilightcraft.maskFromAlpha", params: Session.SelectionRequest(side: 16, alpha: left, name: "Subject", maskID: nil, op: "new"))
        let subject = try decoder.decode(Session.MaskResult.self, from: Data(a.utf8)).activeMask
        let b = try await model.performPhotoEdit("ilightcraft.maskFromAlpha", params: Session.SelectionRequest(side: 16, alpha: right, name: "Background", maskID: nil, op: "new"))
        let background = try decoder.decode(Session.MaskResult.self, from: Data(b.utf8)).activeMask
        var red = MaskColorAdjustments(); red.colorize(hue: 0); red.exposure = 0.3
        var blue = MaskColorAdjustments(); blue.colorize(hue: 240)
        _ = try await model.performPhotoEdit("mask.adjust", params: Session.MaskAdjustment(id: subject, values: red))
        _ = try await model.performPhotoEdit("mask.adjust", params: Session.MaskAdjustment(id: background, values: blue))
        func masks() async throws -> [Session.SavedMask] {
            let text = try await model.photoCommand("develop.get", params: [String: String]())
            return try decoder.decode(Session.MaskList.self, from: Data(text.utf8)).masks
        }
        let both = try await masks()
        #expect(both.first { $0.id == subject }?.adjust == red)
        #expect(both.first { $0.id == background }?.adjust == blue)
        await model.undo()
        let undone = try await masks()
        #expect(undone.first { $0.id == subject }?.adjust == red)
        #expect(undone.first { $0.id == background }?.adjust.colorAmount == 0)
        await model.redo()
        #expect(try await masks().first { $0.id == background }?.adjust == blue)
    }
}
