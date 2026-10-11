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

    /// inspectorRetainsCanvasAndClosesOnTap verifies native touch routing and canvas identity
    /// through the SwiftUI inspector's regular column and compact sheet presentations.
    @Test(arguments: [false, true])
    func inspectorRetainsCanvasAndClosesOnTap(isCompact: Bool) async throws {
        let fixture = try Fixture(isCompact: isCompact)
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        let width = fixture.canvas.bounds.width

        fixture.session.showPanel(.color)
        try await waitUntil(seconds: 3) {
            isCompact
                ? fixture.host.presentedViewController != nil
                : fixture.canvas.bounds.width < width - 100
        }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
        #expect(fixture.session.inspector.selectedGroup == .color)

        fixture.canvas.onSingleTap?()
        try await waitUntil(seconds: 3) {
            !fixture.session.isInspectorPresented && fixture.canvasReceivesCenterTouch
                && abs(fixture.canvas.bounds.width - width) < 1
                && fixture.host.presentedViewController == nil
        }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
    }

    /// adjustmentFailureIsVisibleAboveInspector checks that the compact sheet does not swallow
    /// an editing error. Closing the alert clears the model while leaving the inspector open.
    @Test(arguments: [false, true])
    func adjustmentFailureIsVisibleAboveInspector(isCompact: Bool) async throws {
        let fixture = try Fixture(isCompact: isCompact)
        defer { fixture.window.isHidden = true }
        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        let width = fixture.canvas.bounds.width
        fixture.session.showPanel(.light)
        try await waitUntil(seconds: 3) {
            isCompact
                ? fixture.host.presentedViewController != nil
                : fixture.canvas.bounds.width < width - 100
        }
        try await Task.sleep(for: .milliseconds(500))

        fixture.engine.failNextSet = .engine("Adjustment failed")
        await fixture.model.drag(.exposure, to: 1)
        try await waitUntil(seconds: 3) {
            findAlert(in: fixture.host)?.message == "Adjustment failed"
        }
        #expect(fixture.session.isInspectorPresented)

        fixture.session.dismissAlert()
        try await waitUntil(seconds: 3) { findAlert(in: fixture.host) == nil }
        #expect(fixture.model.errorMessage == nil)
        #expect(fixture.session.isInspectorPresented)
        fixture.host.dismiss(animated: false)
    }

    /// openingPhotoRemovesEmptyState keeps the canvas attached even before an import. Opening
    /// a photo removes the touch-blocking placeholder instead of replacing the Metal view.
    @Test(arguments: [false, true])
    func openingPhotoRemovesEmptyState(isCompact: Bool) async throws {
        let fixture = try Fixture(isCompact: isCompact)
        defer { fixture.window.isHidden = true }
        try await waitUntil(seconds: 3) { !fixture.canvas.bounds.isEmpty }
        #expect(!fixture.canvasReceivesCenterTouch)

        fixture.session.showPanel(.light)
        #expect(!fixture.session.isInspectorPresented)

        await fixture.model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await waitUntil(seconds: 3) { fixture.canvasReceivesCenterTouch }
        #expect(findCanvas(in: fixture.host.view) === fixture.canvas)
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
        let host   : UIHostingController<EditorView<FakeEngine, FakeImporter, PhotoLibraryLoader>>
        let window : UIWindow

        init(isCompact: Bool) throws {
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
            let host = UIHostingController(rootView: EditorView(
                session     : session,
                canvas      : canvas,
                diagnostics : diagnostics
            ))
            host.traitOverrides.horizontalSizeClass = isCompact ? .compact : .regular
            host.traitOverrides.preferredContentSizeCategory = isCompact
                ? .accessibilityExtraExtraExtraLarge
                : .large
            let scene = try #require(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            if isCompact {
                window.frame = CGRect(
                    x      : 0,
                    y      : 0,
                    width  : 320,
                    height : 480
                )
            }
            window.overrideUserInterfaceStyle = isCompact ? .dark : .light
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
