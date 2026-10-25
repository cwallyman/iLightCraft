import Foundation
import Testing
@testable import iLightCraft

@Suite(.serialized)
@MainActor
struct NativeColorToolsTests {
    @Test func eachColorHasThreeDistinctEngineControlsWithCorrectBounds() {
        let controls = HSLColorBand.allCases.flatMap(\.controls)
        #expect(controls.count == 24)
        #expect(Set(controls).count == 24)
        for band in HSLColorBand.allCases {
            #expect(band.controls.map(\.rawValue) == ["hue", "sat", "lum"].map { "mixer.\(band.rawValue).\($0)" })
            for control in band.controls {
                #expect(control.range == -100...100)
                #expect(control.defaultValue == 0 && control.step == 1)
            }
        }
    }

    @Test func hslDragUndoAndRedoRetainAnUnrelatedBasicEdit() async {
        let engine = FakeEngine()
        let model = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 96)
        _ = await model.open(pickedURL: URL(filePath: "/tmp/color-test.png"))
        model.beginDrag(.exposure)
        await model.drag(.exposure, to: 0.5)
        await model.endDrag(.exposure)
        model.beginDrag(.blueSaturation)
        await model.drag(.blueSaturation, to: -30)
        await model.endDrag(.blueSaturation)
        #expect(model.values[.blueSaturation] == -30)
        await model.undo()
        #expect(model.values[.blueSaturation] == 0)
        #expect(model.values[.exposure] == 0.5)
        await model.redo()
        #expect(model.values[.blueSaturation] == -30)
        #expect(model.values[.exposure] == 0.5)
    }

    @Test func profileIDAndAmountAreIncludedInUndoSettings() throws {
        let text = #"{"profile":{"id":"lc.vivid","amount":175},"curve":{"master":[],"red":[],"green":[],"blue":[]}}"#
        let snapshot = try EngineManager.nativeUndoSettings(from: text)
        let object = try #require(JSONSerialization.jsonObject(with: Data(snapshot.utf8)) as? [String: Any])
        let profile = try #require(object["profile"] as? [String: Any])
        #expect(profile["id"] as? String == "lc.vivid")
        #expect(profile["amount"] as? Int == 175)
        #expect(object["curve"] != nil)
    }

    /// Real bridge coverage saved for manual execution; uses only an original generated fixture.
    @Test func selectingAProfileAndChangingItsAmountUndoIndependentlyWithoutLosingHSL() async throws {
        let support = EngineManagerTests()
        let manager = try support.makeManager(maxPixels: 128)
        let fixture = try support.fixtureURL()
        defer { try? FileManager.default.removeItem(at: fixture) }
        let model = EditorViewModel(engine: manager, importer: FakeImporter(), previewPixels: 96)
        #expect(await model.open(pickedURL: fixture))
        model.beginDrag(.redHue)
        await model.drag(.redHue, to: 33)
        await model.endDrag(.redHue)
        let profiles = ProfileEditorSession(model: model)
        await profiles.load(showsPreview: false)
        let menu = try #require(profiles.menu)
        let vivid = try #require(menu.groups.flatMap(\.profiles).first { $0.id == "lc.vivid" })
        await profiles.select(vivid)
        profiles.amount = 175
        await profiles.commitAmount()
        #expect(profiles.selectedID == "lc.vivid" && profiles.amount == 175)
        await profiles.undo(redo: false)
        #expect(profiles.selectedID == "lc.vivid" && profiles.amount == 100)
        #expect(model.values[.redHue] == 33)
        await profiles.undo(redo: false)
        #expect(profiles.selectedID == "lc.color" && profiles.amount == 100)
        #expect(model.values[.redHue] == 33)
        await profiles.undo(redo: true)
        #expect(profiles.selectedID == "lc.vivid" && profiles.amount == 100)
        let count = model.undoStack.count
        await profiles.favorite(vivid)
        #expect(model.undoStack.count == count)
        #expect(profiles.menu?.favorites.contains { $0.id == vivid.id } == true)
    }
}
