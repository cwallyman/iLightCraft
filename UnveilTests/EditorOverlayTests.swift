//
//  EditorOverlayTests.swift
//  UnveilTests
//

import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Unveil

@MainActor
struct EditorOverlayTests {

    /// The overlay covers the whole canvas, and a hosting view claims every point by itself. The
    /// pass-through must hand the touches outside the controls to the canvas (hitTest returns nil)
    /// while the controls still take theirs.
    @Test
    func touchesOutsideTheControlsReachTheCanvas() async throws {
        let model  = EditorViewModel(engine: FakeEngine(), importer: FakeImporter(), previewPixels: 1024)
        let chrome = EditorChrome()
        await model.open(pickedURL: URL(filePath: "/tmp/photo.RAF"))

        let host = UIHostingController(
            rootView: EditorOverlay(
                viewModel       : model,
                chrome          : chrome,
                diagnosticsMenu : UIMenu(),
                onOpen          : {}
            )
        )
        let passthrough = OverlayPassthroughView { Array(chrome.touchableFrames.values) }
        let scene       = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window      = UIWindow(windowScene: scene)
        defer { window.isHidden = true }

        host.view.backgroundColor = .clear
        host.view.frame           = window.bounds
        passthrough.frame         = window.bounds
        passthrough.addSubview(host.view)
        window.addSubview(passthrough)
        window.isHidden = false
        passthrough.layoutIfNeeded()

        try await waitUntil(seconds: 2) {
            chrome.touchableFrames[.leadingBar] != nil && chrome.touchableFrames[.toolbar] != nil
        }

        #expect(model.isPhotoOpen)
        #expect(chrome.touchableFrames[.emptyState] == nil)
        #expect(passthrough.hitTest(CGPoint(x: 500, y: 500), with: nil) == nil)
        #expect(passthrough.hitTest(CGPoint(x: 40, y: 50), with: nil) != nil)
        #expect(passthrough.hitTest(CGPoint(x: window.bounds.width - 60, y: 50), with: nil) != nil)
    }
}
