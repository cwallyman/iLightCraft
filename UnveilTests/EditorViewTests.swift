//
//  EditorViewTests.swift
//  UnveilTests
//

import Metal
import SwiftUI
import Testing
import UIKit
@testable import Unveil

@Suite(.serialized)
@MainActor
struct EditorViewTests {

    /// cardKeepsCanvasAndClosesOnTap verifies native touch routing and canvas identity while the
    /// adjust card opens and closes: the card floats over the canvas and never resizes it.
    @Test
    func cardKeepsCanvasAndClosesOnTap() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        let size = fixture.canvas.bounds.size

        fixture.session.showPanel(.color)
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.session.isCardOpen)
        #expect(fixture.session.selectedGroup == .color)
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
        #expect(fixture.canvas.bounds.size == size)

        fixture.canvas.onSingleTap?()
        try await waitUntil(seconds: 3) {
            !fixture.session.isCardOpen && fixture.canvasReceivesCenterTouch
        }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
        #expect(fixture.canvas.bounds.size == size)
    }

    /// adjustmentFailureIsVisibleWhileCardIsOpen checks that the card does not hide an editing
    /// error. Closing the alert clears the model while leaving the card open.
    @Test
    func adjustmentFailureIsVisibleWhileCardIsOpen() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        fixture.session.showPanel(.light)
        try await Task.sleep(for: .milliseconds(500))

        fixture.engine.failNextSet = .engine("Adjustment failed")
        await fixture.model.drag(.exposure, to: 1)
        try await waitUntil(seconds: 3) {
            findAlert(in: fixture.host)?.message == "Adjustment failed"
        }
        #expect(fixture.session.isCardOpen)

        fixture.session.dismissAlert()
        try await waitUntil(seconds: 3) { findAlert(in: fixture.host) == nil }
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.session.isCardOpen)
    }

    /// openingPhotoKeepsCanvas keeps the canvas attached even before an import (the home, not
    /// the editor, covers that state). Without a photo the Adjust tool does not open the card.
    @Test
    func openingPhotoKeepsCanvas() async throws {
        let fixture = try Fixture()
        defer { fixture.window.isHidden = true }
        try await waitUntil(seconds: 3) { !fixture.canvas.bounds.isEmpty }

        fixture.session.showPanel(.light)
        #expect(!fixture.session.isCardOpen)

        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
    }

    /// canvasSurvivesHomeAndBackWithTheCardClosed hosts the whole workspace: going home and back
    /// keeps the one canvas, and with the card closed it receives a touch at its center.
    @Test
    func canvasSurvivesHomeAndBackWithTheCardClosed() async throws {
        let fixture = try Fixture(hostsWorkspace: true)
        defer { fixture.window.isHidden = true }
        await fixture.session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }

        fixture.session.goHome()
        try await Task.sleep(for: .milliseconds(500))
        #expect(fixture.canvas.window === fixture.window)

        await fixture.session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
        #expect(!fixture.session.isCardOpen)
    }

    private func findCanvas(in view: UIView) -> CanvasView? {
        if let canvas = view as? CanvasView { return canvas }

        for subview in view.subviews {
            if let canvas = findCanvas(in: subview) { return canvas }
        }

        return nil
    }

    private func findAlert(in controller: UIViewController) -> UIAlertController? {
        if let alert = controller as? UIAlertController { return alert }
        if let presented = controller.presentedViewController,
           let alert = findAlert(in: presented)
        { return alert }

        for child in controller.children {
            if let alert = findAlert(in: child) { return alert }
        }

        return nil
    }

    @MainActor
    private struct Fixture {

        let engine : FakeEngine
        let model  : EditorViewModel<FakeEngine, FakeImporter>
        let session: EditorSession<FakeEngine, FakeImporter, PhotoLibraryLoader>
        let canvas : CanvasView
        // AnyView: one fixture hosts either the editor or the whole workspace, chosen at run time.
        let host   : UIHostingController<AnyView>
        let window : UIWindow

        init(hostsWorkspace: Bool = false) throws {
            let engine = FakeEngine()
            let model = EditorViewModel(
                engine        : engine,
                importer      : FakeImporter(),
                previewPixels : 1024
            )
            let session = EditorSession(viewModel: model, libraryLoader: PhotoLibraryLoader())
            let canvas = CanvasView(
                frames : engine.frames,
                device : try #require(MTLCreateSystemDefaultDevice())
            )
            let diagnostics = EditorDiagnostics(
                engine            : engine,
                viewModel         : model,
                possibleTearCount : { [weak canvas] in canvas?.possibleTearCount ?? 0 },
                present           : { [weak session] in session?.alert = $0 }
            )
            let root = hostsWorkspace
                ? AnyView(WorkspaceView(
                    session       : session,
                    canvas        : canvas,
                    diagnostics   : diagnostics,
                    launchOptions : MeasurementLaunchOptions(arguments: [])
                ))
                : AnyView(EditorView(session: session, canvas: canvas, diagnostics: diagnostics))
            let host = UIHostingController(rootView: root)
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.overrideUserInterfaceStyle = .light
            window.rootViewController = host
            window.makeKeyAndVisible()
            window.layoutIfNeeded()

            self.engine  = engine
            self.model   = model
            self.session = session
            self.canvas  = canvas
            self.host    = host
            self.window  = window
        }

        var canvasReceivesCenterTouch: Bool {
            guard !canvas.bounds.isEmpty else { return false }

            let center = canvas.convert(
                CGPoint(x: canvas.bounds.midX, y: canvas.bounds.midY),
                to: window
            )
            return window.hitTest(center, with: nil) === canvas
        }
    }
}
