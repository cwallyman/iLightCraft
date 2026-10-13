//
//  HomeTouchTests.swift
//  UnveilTests
//

import SwiftUI
import Testing
import UIKit
@testable import Unveil

/// HomeTouchTests check where a touch on the home lands. The home's own controls live in the
/// system launch view's foreground accessory, which the launch view treats as backdrop, under the
/// system Files sheet's full-screen containers: both can swallow taps without any visible sign.
@Suite(.serialized, .exclusiveWindow)
@MainActor
struct HomeTouchTests {

    /// theSourcePickerTakesTouchesAboveTheFilesSheet catches an accessory the launch view passes
    /// touches through: the Files / Photos picker above the sheet must reach our hosting view.
    @Test
    func theSourcePickerTakesTouchesAboveTheFilesSheet() async throws {
        let window = try showHome(arguments: [])
        defer { window.isHidden = true }

        let pickerPoint = CGPoint(x: 60, y: window.bounds.height * 0.42)
        try await waitUntil(seconds: 5) {
            ancestry(of: window.hitTest(pickerPoint, with: nil)).first == "_UIHostingView<AnyView>"
        }
    }

    /// theSourcePickerTakesTouchesAboveTheRestingPhotosPanel catches a Photos panel that takes
    /// touches above itself: it is laid out at its expanded size and only moved down at rest, so
    /// the picker above it is reachable only if the empty part of its frame lets touches through.
    @Test
    func theSourcePickerTakesTouchesAboveTheRestingPhotosPanel() async throws {
        let window = try showHome(arguments: ["-UnveilHomePhotos"])
        defer { window.isHidden = true }

        let pickerPoint = CGPoint(x: 60, y: window.bounds.height * 0.42)
        try await waitUntil(seconds: 5) {
            let chain = ancestry(of: window.hitTest(pickerPoint, with: nil))

            return chain.first == "_UIHostingView<AnyView>" && !chain.contains("PassthroughView")
        }
    }

    /// theHiddenFilesSheetLetsThePhotosPanelTakeTouches hosts the home on Photos. The Files sheet
    /// is hidden there, and its full-screen containers must go with it: a point in the Photos
    /// panel has to reach the panel, not the hidden sheet's clipping container.
    @Test
    func theHiddenFilesSheetLetsThePhotosPanelTakeTouches() async throws {
        let window = try showHome(arguments: ["-UnveilHomePhotos"])
        defer { window.isHidden = true }

        let panelPoint = CGPoint(x: window.bounds.midX, y: window.bounds.height * 0.8)
        try await waitUntil(seconds: 5) {
            let chain = ancestry(of: window.hitTest(panelPoint, with: nil))

            return chain.contains { $0.hasPrefix("_UIHostingView<AnyView>") }
                && !chain.contains("_UIDropShadowClippingView")
        }
    }

    /// showHome hosts the real home in its own key window.
    private func showHome(arguments: [String]) throws -> UIWindow {
        let home = HomeView(
            launchOptions : MeasurementLaunchOptions(arguments: arguments),
            isActive      : true,
            isImporting   : false,
            onPickFile    : { _ in },
            onPickPhoto   : { _ in }
        )
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )

        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: home)
        window.makeKeyAndVisible()

        return window
    }

    /// ancestry is the type names from a view up to its window.
    private func ancestry(of view: UIView?) -> [String] {
        var names  = [String]()
        var cursor = view

        while let current = cursor {
            names.append(String(describing: type(of: current)))
            cursor = current.superview
        }
        return names
    }
}
