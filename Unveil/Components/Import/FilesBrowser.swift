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
/// `isInteractive` false stops it taking touches (the home panel is collapsed or importing).
struct FilesBrowser: UIViewControllerRepresentable {

    let onPick       : (URL) -> Void
    let isInteractive: Bool

    func makeUIViewController(context: Context) -> UIDocumentBrowserViewController {
        let browser = UIDocumentBrowserViewController(forOpening: [.rawImage, .image])
        browser.allowsDocumentCreation     = false
        browser.allowsPickingMultipleItems = false
        browser.delegate                   = context.coordinator
        return browser
    }

    func updateUIViewController(
        _ browser: UIDocumentBrowserViewController,
        context  : Context
    ) {
        context.coordinator.onPick            = onPick
        browser.view.isUserInteractionEnabled = isInteractive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPick: onPick)
    }

    final class Coordinator: NSObject, UIDocumentBrowserViewControllerDelegate {

        var onPick: (URL) -> Void

        init(onPick: @escaping (URL) -> Void) {
            self.onPick = onPick
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
