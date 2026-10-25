//
//  iLightCraftApp.swift
//  iLightCraft
//

import SwiftUI

/// iLightCraftApp is the SwiftUI entry point. The delegate adapter owns process services while
/// SwiftUI owns the window and the root view's lifetime.
@main
struct iLightCraftApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView(appDelegate: appDelegate)
        }
        .commands {
            ZoomCommands()
        }
    }
}
