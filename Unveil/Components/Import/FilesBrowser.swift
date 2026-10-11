//
//  FilesBrowser.swift
//  Unveil
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// FilesBrowser embeds the system document browser as a child controller, for opening only:
/// no document creation and a single item. The browser keeps its own Recents, Shared and
/// Browse chrome; the picked URL goes to the caller, whose importer handles scoped access.
struct FilesBrowser: UIViewControllerRepresentable {

    let onPick   : (URL) -> Void
    let onSwipeUp: () -> Void

    func makeUIViewController(context: Context) -> UIDocumentBrowserViewController {
        let browser = UIDocumentBrowserViewController(forOpening: [.rawImage, .image])
        browser.allowsDocumentCreation     = false
        browser.allowsPickingMultipleItems = false
        browser.delegate                   = context.coordinator
        context.coordinator.swipeObserver.attach(to: browser.view)
        return browser
    }

    func updateUIViewController(
        _ browser: UIDocumentBrowserViewController,
        context  : Context
    ) {
        context.coordinator.onPick                  = onPick
        context.coordinator.swipeObserver.onSwipeUp = onSwipeUp
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick, onSwipeUp: onSwipeUp)
    }

    final class Coordinator: NSObject, UIDocumentBrowserViewControllerDelegate {

        var onPick       : (URL) -> Void
        let swipeObserver: PanelSwipeObserver

        init(
            onPick   : @escaping (URL) -> Void,
            onSwipeUp: @escaping () -> Void
        ) {
            self.onPick   = onPick
            swipeObserver = PanelSwipeObserver(onSwipeUp: onSwipeUp)
        }

        func documentBrowser(
            _ controller            : UIDocumentBrowserViewController,
            didPickDocumentsAt urls : [URL]
        ) {
            guard let url = urls.first else { return }

            onPick(url)
        }
    }
}
