//
//  EditorViewModelUndoTests.swift
//  iLightCraftTests
//

import Foundation
import Testing
@testable import iLightCraft

@MainActor
struct EditorViewModelUndoTests {

    /// openModel opens a photo in a model whose stepper bursts commit only when `settle` fires
    /// (or an action flushes them), never on a wall-clock delay.
    private func openModel(
        stored: [DevelopAdjustmentKind: Double] = [:],
        settle: ManualSettle = ManualSettle()
    ) async -> (EditorViewModel<FakeEngine, FakeImporter>, FakeEngine) {
        let engine = FakeEngine()
        let model  = EditorViewModel(
            engine        : engine,
            importer      : FakeImporter(),
            previewPixels : 1024,
            settleNudge   : { await settle.wait() }
        )
        engine.storedValues = stored
        await model.open(pickedURL: URL(filePath: "/tmp/x.JPG"))
        return (model, engine)
    }

    private func edit(
        _ model: EditorViewModel<FakeEngine, FakeImporter>,
        _ kind : DevelopAdjustmentKind,
        to value: Double
    ) async {
        model.beginDrag(kind)
        await model.drag(kind, to: value)
        await model.endDrag(kind)
    }

    @Test
    func undoSendsOnlyTheChangedControlThenOneFullPreviewAndRedoReapplies() async {
        let (model, engine) = await openModel()
        await edit(model, .exposure, to: 0.7)
        let before = engine.calls.count

        await model.undo()

        #expect(Array(engine.calls[before...]) == ["set light.exposure 0.0", "preview 1024 full"])
        #expect(model.values[.exposure] == 0)
        #expect(!model.canUndo && model.canRedo)

        let afterUndo = engine.calls.count
        await model.redo()

        #expect(Array(engine.calls[afterUndo...]) == ["set light.exposure 0.7", "preview 1024 full"])
        #expect(model.values[.exposure] == 0.7)
        #expect(model.canUndo && !model.canRedo)
    }

    @Test
    func aNewEditClearsRedo() async {
        let (model, _) = await openModel()
        await edit(model, .exposure, to: 0.7)
        await model.undo()
        await edit(model, .contrast, to: 10)

        #expect(!model.canRedo)
    }

    @Test
    func aCommitThatChangesNothingRecordsNothing() async {
        let (model, _) = await openModel()
        await edit(model, .exposure, to: 0)

        #expect(!model.canUndo)
    }

    @Test
    func aStepperBurstIsOneStep() async throws {
        let settle          = ManualSettle()
        let (model, engine) = await openModel(settle: settle)

        for _ in 1 ... 5 {
            await model.nudge(.exposure, by: 0.01)
        }
        settle.fire()
        try await waitUntil(seconds: 3) { engine.calls.last == "preview 1024 full" }

        #expect(model.undoStack.count == 1)

        await model.undo()

        #expect(model.values[.exposure] == 0)
        #expect(!model.canUndo)
    }

    @Test
    func undoFlushesAPendingBurstFirst() async {
        let (model, _) = await openModel()
        await model.nudge(.exposure, by: 0.01)

        await model.undo()

        #expect(model.values[.exposure] == 0)
        #expect(model.canRedo)
    }

    @Test
    func resetAllIsOneStepAndUndoRestoresTheValues() async {
        let (model, engine) = await openModel(stored: [.exposure: 1, .contrast: 20])
        engine.edited = true
        await model.open(pickedURL: URL(filePath: "/tmp/y.JPG"))
        await model.resetAll()

        #expect(model.undoStack.count == 1)
        let before = engine.calls.count

        await model.undo()

        let calls = Array(engine.calls[before...])
        #expect(calls.contains("set light.exposure 1.0"))
        #expect(calls.contains("set light.contrast 20.0"))
        #expect(calls.last == "preview 1024 full")
        #expect(model.values[.exposure] == 1)
    }

    @Test
    func undoingBackToAsShotUsesTheWhiteBalanceReset() async {
        let (model, engine) = await openModel()
        await edit(model, .temperature, to: 6000)
        let before = engine.calls.count

        await model.undo()

        #expect(Array(engine.calls[before...]) == ["wb asShot", "preview 1024 full"])
    }

    @Test
    func openingAnotherPhotoClearsBothStacks() async {
        let (model, _) = await openModel()
        await edit(model, .exposure, to: 0.7)
        await edit(model, .contrast, to: 10)
        await model.undo()

        await model.open(pickedURL: URL(filePath: "/tmp/z.JPG"))

        #expect(!model.canUndo && !model.canRedo)
    }

    @Test
    func theStackIsCappedAtOneHundredSteps() async {
        let (model, _) = await openModel()

        for step in 1 ... 105 {
            await edit(model, .exposure, to: Double(step % 2 == 0 ? 1 : 2) + Double(step) * 0.001)
        }

        #expect(model.undoStack.count == 100)
    }

    @Test
    func aFailureMidUndoRereadsTheEngineAndKeepsBothStacks() async {
        let (model, engine) = await openModel(stored: [.exposure: 1, .contrast: 20])
        engine.edited = true
        await model.open(pickedURL: URL(filePath: "/tmp/y.JPG"))
        await model.resetAll()

        // The first set lands (exposure), the second (contrast) fails: a half applied step.
        engine.setsBeforeFailure = 1
        engine.failNextSet       = .timeout("The engine did not answer")
        await model.undo()

        #expect(model.errorMessage != nil)
        #expect(model.values[.exposure] == 1)
        #expect(model.values[.contrast] == 0)
        #expect(model.undoStack.count == 1)
        #expect(model.redoStack.isEmpty)

        let before = engine.calls.count
        await model.undo()

        #expect(Array(engine.calls[before...]) == ["set light.contrast 20.0", "preview 1024 full"])
        #expect(model.values[.contrast] == 20)
        #expect(model.undoStack.isEmpty)
        #expect(model.redoStack.count == 1)
    }

    @Test
    func aCustomWhiteBalanceEqualToTheAsShotNumbersIsNotRestoredAsAsShot() async {
        let (model, engine) = await openModel()
        await edit(model, .temperature, to: 6000)
        await edit(model, .temperature, to: 6500)
        await edit(model, .exposure, to: 0.7)

        for _ in 1 ... 3 {
            await model.undo()
        }
        await model.redo()
        let before = engine.calls.count

        await model.redo()

        #expect(Array(engine.calls[before...]) == ["set wb.temp 6500.0", "preview 1024 full"])
        #expect(!engine.isAsShot)
    }

    @Test
    func aBurstBackToTheAsShotNumberWhileTheEngineIsCustomIsRecorded() async throws {
        let settle          = ManualSettle()
        let (model, engine) = await openModel(settle: settle)

        await model.nudge(.temperature, by: 50)
        await model.nudge(.temperature, by: -50)
        settle.fire()
        try await waitUntil(seconds: 3) { engine.calls.last == "preview 1024 full" }

        #expect(model.canUndo)

        let before = engine.calls.count
        await model.undo()

        #expect(Array(engine.calls[before...]) == ["wb asShot", "preview 1024 full"])
    }

    @Test
    func asShotNumbersThatDifferFromTheDefaultsStillRestoreWithOneWhiteBalanceReset() async {
        let (model, engine) = await openModel(stored: [.temperature: 5000, .tint: 3])
        await edit(model, .temperature, to: 7000)
        let before = engine.calls.count

        await model.undo()

        #expect(Array(engine.calls[before...]) == ["wb asShot", "preview 1024 full"])
        #expect(model.values[.temperature] == 5000)
        #expect(model.values[.tint] == 3)
    }

    @Test
    func theWhiteBalanceModeIsReadOnlyAtOpenAndNeverOnARelease() async {
        let (model, engine) = await openModel()
        let afterOpen = engine.asShotQueries

        for value in [6050.0, 6100, 6150] {
            await model.drag(.temperature, to: value)
        }
        await model.endDrag(.temperature)
        await model.undo()

        #expect(afterOpen == 1)
        #expect(engine.asShotQueries == afterOpen)
        #expect(model.canRedo)
    }

    @Test
    func aFlushedBurstKeepsItsLastPress() async {
        let (model, engine) = await openModel()

        // The press is still waiting in the chain when undo flushes the burst.
        _ = Task.immediate { await model.nudge(.exposure, by: 0.01) }
        await model.undo()

        #expect(engine.calls.contains("set light.exposure 0.01"))
        #expect(model.values[.exposure] == 0)
        #expect(model.canRedo)

        await model.redo()

        #expect(model.values[.exposure] == 0.01)
    }
}
