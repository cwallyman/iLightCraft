//
//  DocumentLaunch.swift
//  iLightCraft
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// DocumentLaunch is the system document launch view (UIDocumentViewController with no document):
/// our backdrop (which carries the centered title; the system one is leading-aligned, so it is
/// left empty) and the system Files browser in a bottom sheet
/// that the system drags between a medium height and full screen. Only this launch view draws the
/// browser on glass fading into its dark background; an embedded browser stays opaque.
///
/// The browser is the only part we do not draw. `showsFiles` false fades the whole sheet out (its
/// presentation's container), so the home can show its own Photos panel in the same place. The sheet's
/// medium detent is replaced with one of the same identifier whose height we know, so the home
/// can line up the source picker and the Photos panel with the sheet (`onLayout`, in window
/// points). The system's own medium detent is private and cannot be measured.
///
/// `onDragging` hears a finger start and stop moving the Files sheet (SheetDragDetector) and
/// `onExpanded` the detent a release lands on: all this process can know of the sheet's motion.
///
/// `background` sits behind the title; `foreground` sits in front of it but behind the sheet, so
/// an expanding sheet covers whatever the foreground puts above it. Both are SwiftUI in hosting
/// controllers the coordinator keeps, whose views the launch view lays out full screen.
struct DocumentLaunch<Background: View, Foreground: View>: UIViewControllerRepresentable {

    let showsFiles    : Bool
    let switchDrift   : CGFloat
    let isInteractive : Bool
    let startsExpanded: Bool
    let onPickFile    : (URL) -> Void
    let onLayout      : (SheetLayout) -> Void
    let onExpanded    : (Bool) -> Void
    let onDragging    : (Bool) -> Void
    let background    : Background
    let foreground    : Foreground

    /// mediumHeightFraction is the medium detent as a share of the sheet's largest height. It is
    /// the system's own medium height measured on an iPad Air 11" in both orientations (0.556
    /// and 0.561), so replacing the detent does not move the sheet.
    static var mediumHeightFraction: CGFloat { 0.56 }

    func makeUIViewController(context: Context) -> UIDocumentViewController {
        let controller = UIDocumentViewController(document: nil)
        let browser    = LaunchBrowserViewController(forOpening: [.rawImage, .image])

        browser.allowsDocumentCreation     = false
        browser.allowsPickingMultipleItems = false
        browser.delegate                   = context.coordinator
        browser.onWillAppear               = { [weak controller, coordinator = context.coordinator] browser in
            guard let controller else { return }
            coordinator.configureSheet(of: browser, in: controller)
        }

        let launchOptions = controller.launchOptions
        launchOptions.browserViewController   = browser
        launchOptions.title                   = ""
        launchOptions.primaryAction           = nil
        launchOptions.secondaryAction         = nil
        launchOptions.backgroundAccessoryView = context.coordinator.accessoryView(of: context.coordinator.backgroundHost)
        launchOptions.foregroundAccessoryView = context.coordinator.accessoryView(of: context.coordinator.foregroundHost)

        return controller
    }

    func updateUIViewController(
        _ controller: UIDocumentViewController,
        context     : Context
    ) {
        context.coordinator.parent                  = self
        context.coordinator.backgroundHost.rootView = AnyView(background)
        context.coordinator.foregroundHost.rootView = AnyView(foreground)

        let browser = controller.launchOptions.browserViewController
        browser.view.isUserInteractionEnabled = isInteractive

        if let container = browser.presentationController?.containerView {
            context.coordinator.show(files: showsFiles, in: container, context: context)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    /// Coordinator owns the two hosting controllers, receives the browser's picks and watches the
    /// sheet's detent. It is the sheet's delegate: the launch view leaves that slot empty.
    final class Coordinator: NSObject, UIDocumentBrowserViewControllerDelegate, UISheetPresentationControllerDelegate {

        var parent: DocumentLaunch

        let backgroundHost = UIHostingController(rootView: AnyView(EmptyView()))
        let foregroundHost = UIHostingController(rootView: AnyView(EmptyView()))

        private var isSheetConfigured = false

        /// drag reads a finger on the Files sheet from the medium detent's resolver calls.
        private var drag    = SheetDragDetector()
        private var dragEnd : DispatchWorkItem?

        /// isFilesShown is the sheet's state as last applied, so an update that does not change
        /// it starts no animation.
        private var isFilesShown = true

        init(parent: DocumentLaunch) {
            self.parent = parent
        }

        /// accessoryView wraps a hosting controller's view in a plain container for the launch
        /// view to place. The launch view treats an accessory view as backdrop: a touch whose hit
        /// test lands on the accessory view itself passes through, and SwiftUI buttons hit the
        /// hosting view itself, so unwrapped they would never get a tap. In the container the
        /// hosting view is a subview, whose touches the launch view keeps.
        ///
        /// The controller cannot be our child: the launch view adopts the accessory views into its
        /// own private controller, and UIKit rejects a child whose view lives elsewhere.
        func accessoryView(of host: UIHostingController<AnyView>) -> UIView {
            let container = UIView()
            host.view.backgroundColor  = .clear
            host.view.frame            = container.bounds
            host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            container.addSubview(host.view)
            return container
        }

        /// show fades the Files sheet in or out with the SwiftUI transaction that changed the
        /// source, so it cross-fades with the Photos panel; leaving, it also sinks by the
        /// parent's `switchDrift`, the way the panel rises. A fade alone is not enough: the
        /// sheet's full-screen container views would still take every touch meant for the Photos
        /// panel below them, so the container stops taking touches at once and is hidden when
        /// the fade ends.
        func show(
            files       : Bool,
            in container: UIView,
            context     : Context
        ) {
            guard files != isFilesShown else { return }

            isFilesShown                       = files
            container.isUserInteractionEnabled = files
            if files {
                container.isHidden = false
            }

            let drift = parent.switchDrift
            context.animate {
                container.alpha     = files ? 1 : 0
                container.transform = files ? .identity : CGAffineTransform(translationX: 0, y: drift)
            } completion: { [weak self, weak container] in
                if self?.isFilesShown == false {
                    container?.isHidden = true
                }
            }
        }

        /// configureSheet runs as the browser's sheet is about to appear, the first moment its
        /// presentation controller exists. It swaps the medium detent for a measurable one, keeps
        /// the system's full detent (whose identifier the launch view leaves undimmed) and opens
        /// at full height when asked.
        func configureSheet(
            of browser       : UIDocumentBrowserViewController,
            in controller    : UIViewController
        ) {
            guard !isSheetConfigured, let sheet = browser.sheetPresentationController else { return }
            guard let medium = sheet.detents.first, let full = sheet.detents.last, sheet.detents.count == 2 else { return }

            isSheetConfigured = true
            sheet.delegate    = self
            if let container = sheet.containerView, !parent.showsFiles {
                isFilesShown                       = false
                container.isHidden                 = true
                container.isUserInteractionEnabled = false
                container.alpha                    = 0
                container.transform                = CGAffineTransform(translationX: 0, y: parent.switchDrift)
            }

            let fraction = DocumentLaunch.mediumHeightFraction
            sheet.detents = [
                .custom(identifier: medium.identifier) { [weak self, weak controller] context in
                    let height = context.maximumDetentValue * fraction
                    self?.noteResolve()

                    // A detent's height leaves out the bottom safe area, so the sheet's top edge
                    // sits that much higher. It is reported after the layout pass that asked.
                    if let controller {
                        let view   = controller.view.bounds.height
                        let insets = controller.view.safeAreaInsets
                        let layout = SheetLayout(restingTop: view - insets.bottom - height, safeTop: insets.top)
                        DispatchQueue.main.async { self?.parent.onLayout(layout) }
                    }
                    return height
                },
                full
            ]

            if parent.startsExpanded {
                sheet.selectedDetentIdentifier = full.identifier
                DispatchQueue.main.async { self.parent.onExpanded(true) }
            }
        }

        func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ sheet: UISheetPresentationController) {
            drag.release(at: CACurrentMediaTime())
            parent.onExpanded(sheet.selectedDetentIdentifier == sheet.detents.last?.identifier)
            finishDrag()
        }

        /// noteResolve passes a resolver call to the drag detector and keeps a timer that ends the
        /// drag 150 ms after the last call, for a release that lands on the same detent (and so
        /// calls no delegate).
        private func noteResolve() {
            if drag.noteResolve(at: CACurrentMediaTime()) {
                parent.onDragging(true)
            }
            guard drag.isDragging else { return }

            dragEnd?.cancel()
            let end = DispatchWorkItem { [weak self] in self?.finishDrag() }
            dragEnd = end
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: end)
        }

        private func finishDrag() {
            dragEnd?.cancel()
            dragEnd = nil
            if drag.end() {
                parent.onDragging(false)
            }
        }

        func documentBrowser(
            _ controller            : UIDocumentBrowserViewController,
            didPickDocumentsAt urls : [URL]
        ) {
            guard let url = urls.first else { return }

            parent.onPickFile(url)
        }
    }
}

/// SheetDragDetector reads a finger on the Files sheet from the outside. The system browser draws
/// and drags the sheet in its own process, and nothing about its position reaches this one; but
/// while a finger moves it, UIKit here lays the sheet out every frame and asks the medium detent
/// for its height each time, about a hundred calls a second, until the release, when the sheet's
/// delegate hears the new detent at once. Four calls within 80 ms start a drag (an ordinary layout
/// pass makes two or three); the layout pass that follows a release is ignored.
nonisolated struct SheetDragDetector {

    private(set) var isDragging = false

    private var recentCalls: [TimeInterval] = []
    private var quietUntil : TimeInterval   = 0

    /// noteResolve records a resolver call and returns true when it starts a drag.
    mutating func noteResolve(at time: TimeInterval) -> Bool {
        guard time > quietUntil else { return false }

        recentCalls = recentCalls.filter { time - $0 < 0.08 } + [time]
        guard !isDragging, recentCalls.count >= 4 else { return false }

        isDragging = true
        return true
    }

    /// release mutes the layout pass a release causes, which would read as a new drag.
    mutating func release(at time: TimeInterval) {
        quietUntil = time + 0.12
    }

    /// end ends a drag and returns whether one was under way.
    mutating func end() -> Bool {
        recentCalls = []
        defer { isDragging = false }
        return isDragging
    }
}

/// SheetLayout is where the Files sheet rests, in window points: its top edge at the medium
/// detent, and the top of the safe area, which its full detent stays below.
struct SheetLayout: Equatable {

    let restingTop: CGFloat
    let safeTop   : CGFloat
}

/// LaunchBrowserViewController is the launch view's Files browser with one hook: it reports when
/// it is about to appear, because the launch view presents it as a sheet on its own schedule and
/// its presentation controller does not exist before.
final class LaunchBrowserViewController: UIDocumentBrowserViewController {

    var onWillAppear: (UIDocumentBrowserViewController) -> Void = { _ in }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        onWillAppear(self)
    }

}
