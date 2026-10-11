//
//  BeforeAfterTests.swift
//  UnveilTests
//

import Foundation
import Metal
import Testing
import UIKit
@testable import Unveil

/// BeforeAfterTests covers the unedited look: the view model's frame requests while it shows, the
/// canvas's hold and VoiceOver action, and a real engine frame that differs from the edited one.
@MainActor
struct BeforeAfterTests {

    private static let zoomWindow = FrameWindow(
        frameWidth  : 6240,
        frameHeight : 4159,
        x           : 1908,
        y           : 1227,
        width       : 2424,
        height      : 1705
    )

    private func openModel() async -> (FakeEngine, EditorViewModel<FakeEngine, FakeImporter>) {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)
        await model.open(pickedURL: URL(filePath: "/tmp/x.RAF"))

        return (engine, model)
    }

    @Test
    func showingBeforeAsksForAFullBeforePreviewAndEndingItForTheEdit() async {
        let (engine, model) = await openModel()
        let start           = engine.calls.count

        await model.setShowingBefore(true)
        #expect(model.isShowingBefore)

        await model.setShowingBefore(false)
        #expect(model.isShowingBefore == false)

        #expect(Array(engine.calls[start...]) == ["preview 1024 full before", "preview 1024 full"])
    }

    @Test
    func aStateThatDidNotChangeAsksForNothing() async {
        let (engine, model) = await openModel()
        let start           = engine.calls.count

        await model.setShowingBefore(false)

        #expect(engine.calls.count == start)
    }

    @Test
    func nothingShowsBeforeWithoutAPhoto() async {
        let engine = FakeEngine()
        let model  = EditorViewModel(engine: engine, importer: FakeImporter(), previewPixels: 1024)

        await model.setShowingBefore(true)

        #expect(model.isShowingBefore == false)
        #expect(engine.calls.isEmpty)
    }

    /// Zoom and windows keep working: the window, and the preview under it, are of the before look too.
    @Test
    func aZoomedBeforeAsksForThePreviewAndTheWindowInTheBeforeLook() async {
        let (engine, model) = await openModel()
        await model.showWindow(Self.zoomWindow, draft: false)
        let start = engine.calls.count

        await model.setShowingBefore(true)
        await model.showWindow(Self.zoomWindow, draft: true)

        #expect(Array(engine.calls[start...]) == [
            "preview 1024 full before",
            "window 1908,1227 2424x1705 of 6240x4159 full before",
            "window 1908,1227 2424x1705 of 6240x4159 draft before"
        ])
    }

    @Test
    func openingAnotherPhotoEndsTheBeforeLook() async {
        let (engine, model) = await openModel()
        await model.setShowingBefore(true)

        await model.open(pickedURL: URL(filePath: "/tmp/y.RAF"))

        #expect(model.isShowingBefore == false)
        #expect(engine.calls.last == "preview 1024 full")
    }

    @Test
    func goingHomeEndsTheBeforeLook() async throws {
        let (_, model) = await openModel()
        let session    = EditorSession(viewModel: model, libraryLoader: PhotoLibraryLoader())
        await model.setShowingBefore(true)

        session.goHome()

        try await waitUntil(seconds: 3) { !model.isShowingBefore }
    }

    private func openSession() async -> (
        EditorViewModel<FakeEngine, FakeImporter>,
        EditorSession<FakeEngine, FakeImporter, PhotoLibraryLoader>
    ) {
        let (_, model) = await openModel()

        return (model, EditorSession(viewModel: model, libraryLoader: PhotoLibraryLoader()))
    }

    /// A hold closes the card at touch-down like any touch, and its release brings the card back.
    @Test
    func aHoldReopensTheCardItsTouchDownClosed() async throws {
        let (model, session) = await openSession()
        session.showPanel(.light)

        session.touchDown()
        #expect(!session.isCardOpen)

        session.holdChanged(true)
        #expect(model.isShowingBefore)
        #expect(!session.isCardOpen)

        session.holdChanged(false)
        #expect(session.isCardOpen)
        try await waitUntil(seconds: 3) { !model.isShowingBefore }
    }

    /// A tap closes the card for good: a later hold, whose touch-down closed nothing, reopens nothing.
    @Test
    func aTapStillClosesTheCardForGood() async throws {
        let (model, session) = await openSession()
        session.showPanel(.light)

        session.touchDown()
        session.touchDown()
        session.holdChanged(true)
        session.holdChanged(false)

        #expect(!session.isCardOpen)
        try await waitUntil(seconds: 3) { !model.isShowingBefore }
    }

    /// A hold returns to the look that was on before it: releasing it keeps a before view that the
    /// keyboard or the menu turned on.
    @Test
    func releasingAHoldKeepsABeforeTheKeyboardTurnedOn() async {
        let (model, session) = await openSession()
        await model.setShowingBefore(true)

        session.touchDown()
        session.holdChanged(true)
        session.holdChanged(false)
        await Task.yield()

        #expect(model.isShowingBefore)
    }

    // MARK: - Canvas

    private func makeCanvas() throws -> CanvasView {
        let device = try #require(MTLCreateSystemDefaultDevice())

        return CanvasView(frames: FrameSink(device: device, maxPixels: 64), device: device)
    }

    /// The hold is one finger, about 0.35 s: a second finger (a pinch) or a move beyond the slop never begins it.
    @Test
    func theCanvasHasASingleFingerHoldOfAboutAThirdOfASecond() throws {
        let canvas = try makeCanvas()
        let holds  = (canvas.gestureRecognizers ?? []).compactMap { $0 as? UILongPressGestureRecognizer }
        let hold   = try #require(holds.first)

        #expect(holds.count == 1)
        #expect(hold.numberOfTouchesRequired == 1)
        #expect(hold.minimumPressDuration == CanvasView.holdDuration)
        #expect(CanvasView.holdDuration == 0.35)
        #expect(hold.allowableMovement == 10)
    }

    /// The hold runs alone: once it begins, a pan, pinch or double tap cannot recognize with it, so
    /// the image stays still under a drifting finger. Pinch and pan still run together.
    @Test
    func theHoldNeverRecognizesWithAPanAPinchOrADoubleTap() throws {
        let canvas      = try makeCanvas()
        let recognizers = canvas.gestureRecognizers ?? []
        let hold        = try #require(recognizers.first { $0 is UILongPressGestureRecognizer })
        let pan         = try #require(recognizers.first { $0 is UIPanGestureRecognizer })
        let pinch       = try #require(recognizers.first { $0 is UIPinchGestureRecognizer })
        let doubleTap   = try #require(
            recognizers.first { ($0 as? UITapGestureRecognizer)?.numberOfTapsRequired == 2 }
        )

        for other in [pan, pinch, doubleTap] {
            #expect(!canvas.gestureRecognizer(hold, shouldRecognizeSimultaneouslyWith: other))
            #expect(!canvas.gestureRecognizer(other, shouldRecognizeSimultaneouslyWith: hold))
        }
        #expect(canvas.gestureRecognizer(pinch, shouldRecognizeSimultaneouslyWith: pan))
    }

    @Test
    func voiceOverGetsAShowOriginalActionThatTogglesTheSameState() throws {
        let canvas  = try makeCanvas()
        var toggles = 0
        canvas.onToggleBefore = { toggles += 1 }

        let action = try #require(canvas.accessibilityCustomActions?.first)
        #expect(action.name == "Show Original")
        #expect(action.actionHandler?(action) == true)
        #expect(toggles == 1)

        canvas.isShowingBefore = true
        #expect(canvas.accessibilityCustomActions?.first?.name == "Show Edited")
    }

    // MARK: - Engine

    /// A real engine frame asked with `before` is the unedited look: it differs from the edited one
    /// of the same photo, and an edited request after it shows the edit again.
    @Test
    func aBeforeFrameFromTheEngineDiffersFromTheEditedOne() async throws {
        let library = FileManager.default.temporaryDirectory.appending(path: "engine-\(UUID())")
        let manager = try EngineManager(dataDirectory: library, maxPixels: 256)
        _ = try await manager.openPhoto(at: EngineManagerTests().fixtureURL())
        try await manager.set(.exposure, to: 2)

        func firstPixel(before: Bool) async throws -> [UInt8] {
            let generation = try manager.requestPreview(
                maxPixels : 96,
                draft     : false,
                before    : before
            )
            try await waitUntil(seconds: 30) { (manager.frames.latest()?.generation ?? 0) >= generation }

            let frame  = try #require(manager.frames.latest())
            let bytes  = manager.frames.buffer(at: frame.bufferIndex).contents().assumingMemoryBound(to: UInt8.self)

            return (0 ..< 4).map { bytes[$0] }
        }

        let edited   = try await firstPixel(before: false)
        let original = try await firstPixel(before: true)
        let again    = try await firstPixel(before: false)

        #expect(edited != original)
        #expect(again == edited)
    }
}
