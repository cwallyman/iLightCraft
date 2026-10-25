//
//  WorkspaceViewTests.swift
//  iLightCraftTests
//

import Metal
import SwiftUI
import Testing
import UIKit
@testable import iLightCraft

@Suite(.exclusiveWindow)
@MainActor
struct WorkspaceViewTests {

    /// failedOpenAlertsOnHomeAndCanvasSurvivesNavigation hosts the real home and editor: a failed
    /// open must show its alert while the editor is hidden, and home and back keeps the canvas.
    @Test
    func failedOpenAlertsOnHomeAndCanvasSurvivesNavigation() async throws {
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
            possibleTearCount : { 0 },
            present           : { [weak session] in session?.show($0) }
        )
        let host = UIHostingController(rootView: WorkspaceView(
            session       : session,
            canvas        : canvas,
            diagnostics   : diagnostics,
            launchOptions : MeasurementLaunchOptions(arguments: [])
        ))
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }

        engine.failNextOpen = .engine("Open failed")
        await session.open(pickedURL: URL(filePath: "/tmp/broken.RAF"))
        #expect(!session.isEditorPresented)
        try await waitUntil(seconds: 3) { host.presentedViewController is UIAlertController }

        session.dismissAlert()
        try await waitUntil(seconds: 3) { host.presentedViewController == nil }

        await session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        #expect(session.isEditorPresented)
        #expect(canvas.window === window)

        session.goHome()
        try await Task.sleep(for: .milliseconds(500))
        #expect(canvas.window === window)

        await session.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))
        try await Task.sleep(for: .milliseconds(500))
        #expect(canvas.window === window)
    }
}
