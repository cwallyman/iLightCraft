//
//  HomePanelTests.swift
//  UnveilTests
//

import PhotosUI
import SwiftUI
import Testing
import UIKit
@testable import Unveil

@MainActor
struct HomePanelTests {

    /// theCoverOwnsTheContentWhileCollapsedAndIsGoneWhenExpanded hosts the real home. Collapsed,
    /// a point in the browser area must hit the drag cover and the browsers must refuse touches;
    /// expanded, the cover is hidden and the visible browser is live.
    @Test
    func theCoverOwnsTheContentWhileCollapsedAndIsGoneWhenExpanded() async throws {
        let collapsed = try host(arguments: [])
        defer { collapsed.window.isHidden = true }

        let contentPoint = CGPoint(
            x: collapsed.window.bounds.midX,
            y: collapsed.window.bounds.height * 0.8
        )
        try await waitUntil(seconds: 3) {
            collapsed.window.hitTest(contentPoint, with: nil) is PanelDragSurface.SurfaceView
        }

        #expect(browserViews(in: collapsed.host).count == 2)
        #expect(browserViews(in: collapsed.host).allSatisfy { !$0.isUserInteractionEnabled })

        collapsed.window.isHidden = true

        let expanded = try host(arguments: ["-UnveilHomeExpanded"])
        defer { expanded.window.isHidden = true }

        try await waitUntil(seconds: 3) {
            browserViews(in: expanded.host).contains { $0.isUserInteractionEnabled }
        }

        #expect(surfaces(in: expanded.window).allSatisfy { $0.isHidden })
        #expect(!(expanded.window.hitTest(contentPoint, with: nil) is PanelDragSurface.SurfaceView))
    }

    /// expandingSwitchesTheCoverOffAtOnceAndNeverResizesTheBrowsers expands the collapsed home
    /// through the cover and samples it during the snap: the cover must be off well before the
    /// spring ends, and the browsers must only move, never change size.
    @Test
    func expandingSwitchesTheCoverOffAtOnceAndNeverResizesTheBrowsers() async throws {
        let home = try host(arguments: [])
        defer { home.window.isHidden = true }

        try await waitUntil(seconds: 3) {
            browserViews(in: home.host).count == 2 && !surfaces(in: home.window).isEmpty
        }

        let cover    = try #require(surfaces(in: home.window).first)
        let browsers = browserViews(in: home.host)
        let sizes    = browsers.map(\.bounds.size)

        #expect(cover.accessibilityActivate())
        try await waitUntil(seconds: HomePanelGeometry.snapDuration / 2) { cover.isHidden }

        var hasResized = false
        let deadline   = ContinuousClock.now + .seconds(HomePanelGeometry.snapDuration + 0.2)
        while ContinuousClock.now < deadline {
            hasResized = hasResized || browsers.map(\.bounds.size) != sizes
            try await Task.sleep(for: .milliseconds(8))
        }

        #expect(!hasResized)
        #expect(browsers.contains { $0.isUserInteractionEnabled })
    }

    private func host(arguments: [String]) throws -> (host: UIViewController, window: UIWindow) {
        let home = HomeView(
            launchOptions : MeasurementLaunchOptions(arguments: arguments),
            isActive      : true,
            isImporting   : false,
            onPickFile    : { _ in },
            onPickPhoto   : { _ in }
        )
        let host  = UIHostingController(rootView: home)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )

        let window = UIWindow(windowScene: scene)
        window.rootViewController = host
        window.makeKeyAndVisible()
        window.layoutIfNeeded()

        return (host, window)
    }

    /// browserViews are the root views of the two embedded system browsers, found among the
    /// hosting controller's descendants.
    private func browserViews(in controller: UIViewController) -> [UIView] {
        let own = controller is UIDocumentBrowserViewController || controller is PHPickerViewController

        return (own ? [controller.view] : []) + controller.children.flatMap { browserViews(in: $0) }
    }

    private func surfaces(in view: UIView) -> [UIView] {
        let own = view is PanelDragSurface.SurfaceView

        return (own ? [view] : []) + view.subviews.flatMap { surfaces(in: $0) }
    }
}
