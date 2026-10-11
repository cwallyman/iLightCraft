//
//  EditorViewModelTests.swift
//  UnveilTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Unveil

@MainActor
struct EditorViewModelTests {

    @Test
    func dragSendsValueThenDraftPreviewAndReleaseSendsFull() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        model.beginDrag(.exposure)
        await model.drag(.exposure, to: 0.7)
        await model.endDrag(.exposure)

        #expect(engine.calls == ["set light.exposure 0.7", "preview 1024 draft", "preview 1024 full"])
    }

    @Test
    func valuesAreClampedToTheControlRange() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.drag(.exposure, to: 99)

        #expect(model.values[.exposure] == DevelopAdjustmentKind.exposure.range.upperBound)
    }

    @Test
    func anEngineErrorBecomesAMessageNotACrash() async {
        let engine = FakeEngine()
        engine.failNextOpen = .engine("unsupported camera")
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))

        #expect(model.errorMessage?.contains("unsupported camera") == true)
        #expect(model.openPhoto == nil)
    }

    @Test
    func openingAPhotoShowsAFullPreviewAndDismissClearsTheError() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))

        #expect(model.openPhoto == PhotoID(rawValue: 1))
        #expect(engine.calls == ["open /tmp/x.ARW", "preview 1024 full"])

        engine.failNextOpen = .io("disk full")
        await model.open(pickedURL: URL(filePath: "/tmp/y.ARW"))
        #expect(model.errorMessage == "disk full")

        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    @Test
    func openingAPhotoLoadsTheValuesTheEngineHolds() async {
        let engine = FakeEngine()
        engine.storedValues = [.exposure: 1.5]
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        #expect(model.isPhotoOpen == false)

        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))

        #expect(model.isPhotoOpen)
        #expect(model.values[.exposure] == 1.5)
        #expect(model.values[.temperature] == DevelopAdjustmentKind.temperature.defaultValue)
    }

    /// The engine opened the new photo but its values could not be read: the model keeps the first
    /// photo and its values, and the engine is put back on it, with no preview of the new one.
    @Test
    func anOpenThatFailsHalfwayLeavesBothOnThePreviousPhoto() async {
        let engine = FakeEngine()
        engine.storedValues = [.exposure: 1.5]
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))
        engine.failNextValues = .timeout("develop.controls timed out")
        engine.storedValues   = [.exposure: -2]
        await model.open(pickedURL: URL(filePath: "/tmp/y.ARW"))

        #expect(model.openPhoto == PhotoID(rawValue: 1))
        #expect(model.values[.exposure] == 1.5)
        #expect(model.errorMessage?.contains("timed out") == true)
        #expect(engine.calls == ["open /tmp/x.ARW", "preview 1024 full", "open /tmp/y.ARW", "select 1"])
    }

    /// A failed open must not leave its copy behind: the real importer, on a folder of its own.
    @Test
    func aFailedOpenLeavesNoCopy() async throws {
        let imports = FileManager.default.temporaryDirectory.appending(path: "imports-\(UUID())")
        let picked  = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID()).ARW")
        try Data(UUID().uuidString.utf8).write(to: picked)

        let engine = FakeEngine()
        engine.failNextOpen = .engine("unsupported camera")
        let model  = EditorViewModel(
            engine        : engine,
            importer      : PhotoImporter(importsDirectory: imports),
            previewPixels : 1024
        )

        await model.open(pickedURL: picked)

        #expect(model.openPhoto == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: imports.path(percentEncoded: false)).isEmpty)
    }

    /// The drags and the release are started without awaiting each other, like a finger that moves
    /// faster than the engine. FakeEngine.set yields, so an unchained release would run ahead, and
    /// the stale drags must collapse into far fewer than 40 `set` calls.
    @Test
    func rapidDragsThenReleaseEndWithTheFinalValueBeforeTheFullPreview() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        var tasks  = [Task<Void, Never>]()

        for step in 1 ... 40 {
            let value = Double(step) / 10
            tasks.append(Task { await model.drag(.exposure, to: value) })
        }
        tasks.append(Task { await model.endDrag(.exposure) })

        for task in tasks {
            await task.value
        }

        let calls = engine.calls
        let sets  = calls.filter { $0.hasPrefix("set ") }

        #expect(sets.count < 20)
        #expect(sets.last == "set light.exposure 4.0")
        #expect(calls.last == "preview 1024 full")
        #expect(calls.firstIndex(of: "preview 1024 full") == calls.count - 1)
        #expect(model.values[.exposure] == 4.0)
    }

    /// Drags are interleaved with yields so some links run in the middle of the gesture: the engine
    /// then receives several values, and none of them may be older than the one before it.
    @Test
    func theEngineNeverReceivesAnOlderValueAfterANewerOne() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        var tasks  = [Task<Void, Never>]()

        for step in 1 ... 60 {
            let value = Double(step) / 20
            tasks.append(Task { await model.drag(.exposure, to: value) })
            await Task.yield()
        }
        tasks.append(Task { await model.endDrag(.exposure) })

        for task in tasks {
            await task.value
        }

        let sent = engine.calls
            .filter { $0.hasPrefix("set light.exposure ") }
            .compactMap { Double($0.dropFirst("set light.exposure ".count)) }

        #expect(sent.count < 60)
        #expect(sent == sent.sorted())
        #expect(sent.last == 3.0)
        #expect(engine.calls.last == "preview 1024 full")
    }

    @Test
    func theStatusFollowsTheEnginesEditedFlagAfterOpenAndRelease() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        // Values off their defaults, but the engine says unedited: the status trusts the engine.
        engine.storedValues = [.contrast: 10]
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))
        #expect(!model.isEdited)

        engine.edited = true
        let readsBeforeDrag = engine.editedReads
        await model.drag(.exposure, to: 0.5)
        #expect(engine.editedReads == readsBeforeDrag)
        #expect(!model.isEdited)

        await model.endDrag(.exposure)
        #expect(model.isEdited)

        engine.edited = false
        await model.drag(.exposure, to: 0)
        await model.endDrag(.exposure)
        #expect(!model.isEdited)

        engine.edited = true
        await model.open(pickedURL: URL(filePath: "/tmp/y.ARW"))
        #expect(model.isEdited)
    }

    @Test
    func theTitleIsThePickedFileNameWithoutItsExtension() async {
        let model = EditorViewModel(engine: FakeEngine(), importer: FakeImporter(), previewPixels: 1024)

        #expect(model.photoTitle == "Photo")

        await model.open(pickedURL: URL(filePath: "/tmp/DSCF0042.RAF"))
        #expect(model.photoTitle == "DSCF0042")
        #expect(model.photoType != nil)

        await model.open(pickedURL: URL(filePath: "/tmp/other.ARW"), title: "Custom")
        #expect(model.photoTitle == "Custom")
    }

    @Test
    func aFailedOpenKeepsThePreviousTitle() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.open(pickedURL: URL(filePath: "/tmp/first.ARW"))
        engine.failNextOpen = .engine("unsupported camera")
        await model.open(pickedURL: URL(filePath: "/tmp/second.ARW"))

        #expect(model.photoTitle == "first")
    }

    @Test
    func resetAllOnAPlainImageResetsOnlyThenRereadsAndRendersOnce() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.edited       = true
        engine.storedValues = [.exposure: 1, .tint: 20]
        await model.open(pickedURL: URL(filePath: "/tmp/x.JPG"))
        engine.edited = false
        let before = engine.calls.count

        await model.resetAll()

        #expect(Array(engine.calls[before...]) == ["reset 1", "preview 1024 full"])
        #expect(model.values[.exposure] == DevelopAdjustmentKind.exposure.defaultValue)
        #expect(!model.isEdited)
    }

    @Test
    func resettingTemperatureReturnsWhiteBalanceToAsShot() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.storedValues = [.temperature: 5200]
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))
        engine.edited = true
        await model.drag(.temperature, to: 7000)
        await model.endDrag(.temperature)
        engine.edited = false
        let before = engine.calls.count

        await model.reset(.temperature)

        #expect(Array(engine.calls[before...]) == ["wb asShot", "preview 1024 full"])
        #expect(model.values[.temperature] == 5200)
        #expect(!model.isEdited)
    }

    @Test
    func resettingAnotherControlSendsItsDefault() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))
        await model.drag(.exposure, to: 1)
        await model.endDrag(.exposure)
        let before = engine.calls.count

        await model.reset(.exposure)

        #expect(Array(engine.calls[before...]) == [
            "set light.exposure 0.0",
            "preview 1024 draft",
            "preview 1024 full",
        ])
        #expect(!model.isEdited)
    }

    @Test
    func openReadsThePhotosPixelSize() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.photoInfo = .raf

        await model.open(pickedURL: URL(filePath: "/tmp/x.RAF"))

        #expect(model.photoSize == CGSize(width: 6240, height: 4160))
    }

    @Test
    func aFreshRawWithItsImportDetailIsOriginal() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.photoInfo    = .raf
        engine.storedValues = [.sharpening: 40, .colorNoise: 25, .temperature: 6500, .tint: 0]

        await model.open(pickedURL: URL(filePath: "/tmp/DSCF0267.RAF"))

        #expect(model.defaultValue(of: .sharpening) == 40)
        #expect(model.defaultValue(of: .colorNoise) == 25)
        #expect(!model.isEdited)
    }

    @Test
    func resetAllOnARawWithEmbeddedLensMergesItsCameraDefaultsBack() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.photoInfo    = .dngWithLens
        engine.storedValues = [.sharpening: 90]
        engine.edited       = true
        await model.open(pickedURL: URL(filePath: "/tmp/x.DNG"))
        engine.edited = false
        let before = engine.calls.count

        await model.resetAll()

        #expect(Array(engine.calls[before...]) == [
            "reset 1",
            #"merge {"detail":{"nr_color":25,"sharpen_amount":40},"optics":{"lens_profile":true}}"#,
            "preview 1024 full",
        ])
        #expect(model.values[.sharpening] == 40)
        #expect(model.values[.colorNoise] == 25)
        #expect(!model.isEdited)
    }

    @Test
    func photoInfoReadsEmbeddedLensOnlyForItsPresence() throws {
        let base     = #""width":4032,"height":3024,"kind":"raw","format":"DNG","as_shot_wb":[5600,2]"#
        let withLens = try JSONDecoder().decode(
            PhotoInfo.self,
            from: Data("{\(base),\"embedded_lens\":{\"warp\":[1,0,0]}}".utf8)
        )
        let without  = try JSONDecoder().decode(PhotoInfo.self, from: Data("{\(base)}".utf8))

        #expect(withLens.hasEmbeddedLens)
        #expect(withLens.cameraDefaultsMerge.optics == .init(lensProfile: true))
        #expect(!without.hasEmbeddedLens)
        #expect(without.cameraDefaultsMerge.optics == nil)
        #expect(without.cameraDefaultsMerge.detail == PhotoInfo.rawDetail)
    }

    @Test
    func resetAllOnARawWithoutEmbeddedLensMergesOnlyTheDetail() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.photoInfo = .raf
        engine.edited    = true
        await model.open(pickedURL: URL(filePath: "/tmp/x.RAF"))
        let before = engine.calls.count

        await model.resetAll()

        #expect(engine.calls[before + 1] == #"merge {"detail":{"nr_color":25,"sharpen_amount":40}}"#)
    }

    @Test
    func resetAllRereadsAndRendersEvenWhenTheMergeFails() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.photoInfo    = .dngWithLens
        engine.storedValues = [.sharpening: 90, .exposure: 1]
        engine.edited       = true
        await model.open(pickedURL: URL(filePath: "/tmp/x.DNG"))
        engine.failNextMerge = .engine("merge refused")
        let readsBefore      = engine.editedReads
        let before           = engine.calls.count

        await model.resetAll()

        #expect(Array(engine.calls[before...]).first == "reset 1")
        #expect(engine.calls.last == "preview 1024 full")
        #expect(model.values[.exposure] == 0)
        #expect(model.values[.sharpening] == 0)
        #expect(engine.editedReads == readsBefore + 1)
        #expect(model.isEdited)
        #expect(model.errorMessage == EngineError.engine("merge refused").message)
    }

    @Test
    func resettingSharpeningOnARawGoesBackToForty() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.photoInfo    = .raf
        engine.storedValues = [.sharpening: 40, .colorNoise: 25]
        await model.open(pickedURL: URL(filePath: "/tmp/x.RAF"))
        await model.drag(.sharpening, to: 90)
        await model.endDrag(.sharpening)

        await model.reset(.sharpening)

        #expect(model.values[.sharpening] == 40)
        #expect(!model.isEdited)
    }

    @Test
    func aNonRawKeepsTheControlDefaults() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        engine.storedValues = [.sharpening: 40]

        await model.open(pickedURL: URL(filePath: "/tmp/x.JPG"))

        #expect(model.defaultValue(of: .sharpening) == 0)
        #expect(model.defaultValue(of: .colorNoise) == 0)
    }

    @Test
    func resetAllDoesNothingWhenNothingIsEdited() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.resetAll()

        #expect(engine.calls.isEmpty)
    }

    // MARK: - Stepper bursts

    /// A held stepper repeats its press: every press sends a draft, and exactly one full preview
    /// (the burst's commit) follows once the presses stop, then the edited flag is read.
    @Test
    func aStepperBurstSendsDraftsThenExactlyOneFullPreview() async throws {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine           : engine,
            importer         : FakeImporter(),
            previewPixels    : 1024,
            nudgeSettleDelay : .milliseconds(150)
        )
        await model.open(pickedURL: URL(filePath: "/tmp/x.JPG"))
        let afterOpen = engine.calls.count
        let reads     = engine.editedReads

        for _ in 1 ... 5 {
            await model.nudge(.exposure, by: 0.01)
        }

        let burst = Array(engine.calls.dropFirst(afterOpen))
        #expect(model.values[.exposure] == 0.05)
        #expect(burst.contains("set light.exposure 0.05"))
        #expect(burst.allSatisfy { $0.hasPrefix("set ") || $0 == "preview 1024 draft" })

        try await waitUntil(seconds: 3) { engine.calls.last == "preview 1024 full" }
        try await Task.sleep(for: .milliseconds(400))

        let fulls = engine.calls.dropFirst(afterOpen).filter { $0 == "preview 1024 full" }
        #expect(fulls.count == 1)
        #expect(engine.calls.last == "preview 1024 full")
        #expect(engine.editedReads == reads + 1)
    }

    /// A press on another control, or a slider drag, commits the burst in progress first, so the
    /// two edits stay apart and each ends with its own full preview.
    @Test
    func anotherControlOrADragCommitsTheBurstFirst() async throws {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine           : engine,
            importer         : FakeImporter(),
            previewPixels    : 1024,
            nudgeSettleDelay : .seconds(10)
        )

        await model.nudge(.contrast, by: 1)
        await model.nudge(.clarity, by: -1)

        #expect(engine.calls == [
            "set light.contrast 1.0", "preview 1024 draft",
            "preview 1024 full",
            "set effects.clarity -1.0", "preview 1024 draft"
        ])

        model.beginDrag(.exposure)
        await model.drag(.exposure, to: 0.5)
        await model.endDrag(.exposure)

        #expect(Array(engine.calls.suffix(4)) == [
            "preview 1024 full",
            "set light.exposure 0.5", "preview 1024 draft",
            "preview 1024 full"
        ])
    }

    @Test
    func aStepperPressSnapsToTheStepAndStopsAtTheRange() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine           : engine,
            importer         : FakeImporter(),
            previewPixels    : 1024,
            nudgeSettleDelay : .seconds(10)
        )

        await model.drag(.exposure, to: 4.995)
        await model.nudge(.exposure, by: 0.01)
        await model.nudge(.exposure, by: 0.01)

        #expect(model.values[.exposure] == 5)
    }

    /// Reset All commits a waiting burst first: the burst ends with its own full preview before
    /// the reset reaches the engine, and its timer adds nothing afterwards.
    @Test
    func resetAllCommitsAWaitingBurstFirst() async throws {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine           : engine,
            importer         : FakeImporter(),
            previewPixels    : 1024,
            nudgeSettleDelay : .milliseconds(150)
        )
        engine.edited = true
        await model.open(pickedURL: URL(filePath: "/tmp/x.JPG"))
        let before = engine.calls.count

        await model.nudge(.exposure, by: 0.01)
        await model.resetAll()
        try await Task.sleep(for: .milliseconds(400))

        #expect(Array(engine.calls[before...]) == [
            "set light.exposure 0.01", "preview 1024 draft",
            "preview 1024 full",
            "reset 1", "preview 1024 full"
        ])
    }

    /// A white balance reset commits a waiting burst first, as Reset All does.
    @Test
    func aWhiteBalanceResetCommitsAWaitingBurstFirst() async throws {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine           : engine,
            importer         : FakeImporter(),
            previewPixels    : 1024,
            nudgeSettleDelay : .milliseconds(150)
        )
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))
        let before = engine.calls.count

        await model.nudge(.tint, by: 1)
        await model.reset(.temperature)
        try await Task.sleep(for: .milliseconds(400))

        #expect(Array(engine.calls[before...]) == [
            "set wb.tint 1.0", "preview 1024 draft",
            "preview 1024 full",
            "wb asShot", "preview 1024 full"
        ])
    }

    /// An open commits a waiting burst first, on the photo it edited: its full preview and edited
    /// read come before the new photo is opened.
    @Test
    func anOpenCommitsAWaitingBurstFirst() async throws {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine           : engine,
            importer         : FakeImporter(),
            previewPixels    : 1024,
            nudgeSettleDelay : .milliseconds(150)
        )
        await model.open(pickedURL: URL(filePath: "/tmp/first.JPG"))
        let before = engine.calls.count
        let reads  = engine.editedReads

        await model.nudge(.contrast, by: 1)
        await model.open(pickedURL: URL(filePath: "/tmp/second.JPG"))
        try await Task.sleep(for: .milliseconds(400))

        #expect(Array(engine.calls[before...]) == [
            "set light.contrast 1.0", "preview 1024 draft",
            "preview 1024 full",
            "open /tmp/second.JPG", "preview 1024 full"
        ])
        #expect(engine.editedReads == reads + 2)
    }
}
