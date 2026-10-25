//
//  EditorViewModelFailureTests.swift
//  iLightCraftTests
//

import Foundation
import Testing
@testable import iLightCraft

/// EditorViewModelFailureTests covers how the editor takes errors: a failed render, errors queued
/// behind the one on screen, and the rollback of an open that failed halfway.
@MainActor
struct EditorViewModelFailureTests {

    private func makeModel(_ engine: FakeEngine = FakeEngine()) -> EditorViewModel<FakeEngine, FakeImporter> {
        EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
    }

    /// The engine reported the open's preview as failed: a banner message, no blocking alert.
    @Test
    func aFailedPreviewShowsABannerAndNoAlert() async throws {
        let engine = FakeEngine()
        let model  = makeModel(engine)
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))

        engine.frames.receiveFailure(FrameFailure(generation: 1, isWindow: false, message: "cannot decode"))

        try await waitUntil(seconds: 3) { model.renderErrorMessage == "cannot decode" }
        #expect(model.errorMessage == nil)
        #expect(model.isPhotoOpen)
    }

    @Test
    func aFailedWindowIsNotReported() async throws {
        let engine = FakeEngine()
        let model  = makeModel(engine)
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))

        engine.frames.receiveFailure(FrameFailure(generation: 2, isWindow: true, message: "no window"))
        engine.frames.receiveFailure(FrameFailure(generation: 3, isWindow: false, message: "marker"))

        try await waitUntil(seconds: 3) { model.renderErrorMessage == "marker" }
        #expect(model.errorMessage == nil)
    }

    /// A new preview request clears the banner, and a failure of an older preview is ignored.
    @Test
    func aNewPreviewClearsTheBannerAndAnOlderFailureIsIgnored() async throws {
        let engine = FakeEngine()
        let model  = makeModel(engine)
        await model.open(pickedURL: URL(filePath: "/tmp/x.ARW"))

        engine.frames.receiveFailure(FrameFailure(generation: 1, isWindow: false, message: "first"))
        try await waitUntil(seconds: 3) { model.renderErrorMessage == "first" }

        await model.drag(.exposure, to: 0.5)
        await model.endDrag(.exposure)
        #expect(model.renderErrorMessage == nil)

        engine.frames.receiveFailure(FrameFailure(generation: 1, isWindow: false, message: "stale"))
        engine.frames.receiveFailure(FrameFailure(generation: 99, isWindow: false, message: "marker"))
        try await waitUntil(seconds: 3) { model.renderErrorMessage == "marker" }
    }

    /// A second error raised while the first is unacknowledged waits behind it; an identical one coalesces.
    @Test
    func aSecondErrorWaitsBehindTheFirstAndIdenticalOnesCoalesce() async {
        let engine = FakeEngine()
        let model  = makeModel(engine)

        engine.failNextOpen = .engine("first")
        await model.open(pickedURL: URL(filePath: "/tmp/a.ARW"))
        engine.failNextOpen = .engine("second")
        await model.open(pickedURL: URL(filePath: "/tmp/b.ARW"))
        engine.failNextOpen = .engine("first")
        await model.open(pickedURL: URL(filePath: "/tmp/c.ARW"))

        #expect(model.errorMessage == "first")
        #expect(model.errorMessages == ["first", "second"])

        model.dismissError()
        #expect(model.errorMessage == "second")

        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    /// The photo that was relinked to the new copy points at it: a later failure of the open must
    /// keep that file, while a copy for a photo the engine never returned is still deleted.
    @Test
    func anOpenThatFailsAfterTheEngineReturnedAPhotoKeepsItsCopy() async throws {
        let imports = FileManager.default.temporaryDirectory.appending(path: "imports-\(UUID())")
        let picked  = FileManager.default.temporaryDirectory.appending(path: "picked-\(UUID()).ARW")
        try Data(UUID().uuidString.utf8).write(to: picked)

        let engine = FakeEngine()
        engine.failNextValues = .timeout("develop.controls timed out")
        let model  = EditorViewModel(
            engine        : engine,
            importer      : PhotoImporter(importsDirectory: imports),
            previewPixels : 1024
        )

        await model.open(pickedURL: picked)

        #expect(model.openPhoto == nil)
        #expect(model.errorMessage?.contains("timed out") == true)
        let kept = try FileManager.default.contentsOfDirectory(atPath: imports.path(percentEncoded: false))
        #expect(kept.count == 1)
    }
}
