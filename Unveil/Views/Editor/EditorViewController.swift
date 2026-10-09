//
//  EditorViewController.swift
//  Unveil
//

import Metal
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// EditorViewController is the editor screen: the Metal canvas fills the view and a transparent
/// SwiftUI overlay (EditorOverlay) floats the empty state, the glass bars and the adjustment
/// panels over it. The navigation bar is hidden. Both sides share EditorChrome: the overlay opens
/// panels from its toolbar, and a single tap on the canvas closes the open one.
///
/// The document picker delegate conformance lives in this primary declaration on purpose: the class
/// is generic, and an extension of a generic class cannot add an Objective-C conformance.
///
/// Errors are shown from `updateProperties()`. UIKit tracks the `@Observable` reads made there, so a
/// new `errorMessage` calls it again and the alert appears; its OK button clears the message through
/// `dismissError()`. A new `openPhoto` comes through the same way and returns the canvas to fit.
final class EditorViewController<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: UIViewController,
    UIDocumentPickerDelegate {

    private let viewModel: EditorViewModel<Engine, Importer>
    private let engine   : Engine
    private let canvas   : CanvasView
    private let chrome   = EditorChrome()

    private var soakTest  : StressSweep<Engine, Importer>?
    private var shownPhoto: PhotoID?

    init(
        viewModel: EditorViewModel<Engine, Importer>,
        engine   : Engine,
        device   : some MTLDevice
    ) {
        self.viewModel = viewModel
        self.engine    = engine
        self.canvas    = CanvasView(frames: engine.frames, device: device)

        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("EditorViewController is built in code, not from a storyboard")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(white: 0.11, alpha: 1)
        navigationController?.setNavigationBarHidden(true, animated: false)

        installCanvas()
        installOverlay()

        canvas.onSingleTap = { [chrome] in chrome.close() }
    }

    override func updateProperties() {
        super.updateProperties()

        if viewModel.openPhoto != shownPhoto {
            shownPhoto = viewModel.openPhoto
            canvas.resetZoom()
        }

        guard let message = viewModel.errorMessage, presentedViewController == nil else { return }

        let alert = UIAlertController(
            title          : "Something went wrong",
            message        : message,
            preferredStyle : .alert
        )

        let dismiss = UIAlertAction(title: "OK", style: .default) { [viewModel] _ in
            viewModel.dismissError()
        }

        alert.addAction(dismiss)

        present(alert, animated: true)
    }

    /// showPanel(_:) opens an adjustment panel as its toolbar segment would. Launch arguments use
    /// it (`-UnveilPanel`), so a panel can be shown and captured with no tap.
    func showPanel(_ group: AdjustmentGroup) {
        if chrome.openGroup != group {
            chrome.toggle(group)
        }
    }

    // MARK: - UIDocumentPickerDelegate

    func documentPicker(
        _ controller           : UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        guard let pickedURL = urls.first else { return }

        Task { await viewModel.open(pickedURL: pickedURL) }
    }

    // MARK: - Layout

    private func installCanvas() {
        view.addSubview(canvas)
        pin(canvas, to: view)
    }

    /// pin(_:to:) makes `subview` fill `container` edge to edge.
    private func pin(_ subview: UIView, to container: UIView) {
        subview.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            subview.topAnchor.constraint(equalTo: container.topAnchor),
            subview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
    }

    /// installOverlay hosts the floating UI (placeholder, glass bars, panel) over the canvas, inside
    /// an OverlayPassthroughView so touches outside the controls fall through to the canvas.
    private func installOverlay() {
        let diagnosticsMenu = DiagnosticsMenu.make(
            engine            : engine,
            isPhotoOpen       : { [viewModel] in viewModel.isPhotoOpen },
            possibleTearCount : { [canvas] in canvas.possibleTearCount },
            present           : { [weak self] alert in self?.present(alert, animated: true) },
            startSoakTest     : { [weak self] in self?.startSoakTest() }
        )

        let overlay = UIHostingController(
            rootView: EditorOverlay(
                viewModel       : viewModel,
                chrome          : chrome,
                diagnosticsMenu : diagnosticsMenu,
                onOpen          : { [weak self] in self?.presentDocumentPicker() }
            )
        )
        let passthrough = OverlayPassthroughView { [chrome] in Array(chrome.touchableFrames.values) }
        overlay.view.backgroundColor = .clear

        addChild(overlay)
        passthrough.addSubview(overlay.view)
        view.addSubview(passthrough)

        pin(passthrough, to: view)
        pin(overlay.view, to: passthrough)

        overlay.didMove(toParent: self)
    }

    /// startSoakTest runs the 10-minute StressSweep on the open photo. It does nothing with no photo
    /// open, or while a sweep already runs, and shows where the CSV went when the sweep ends.
    private func startSoakTest() {
        guard viewModel.isPhotoOpen, soakTest == nil else { return }

        let sweep = StressSweep(viewModel: viewModel, duration: 600) { [weak self] isComplete, csv in
            self?.soakTest = nil

            let title = isComplete ? "Soak test finished" : "Soak test stopped early"
            let alert = UIAlertController(
                title          : title,
                message        : "Memory samples: Documents/measurements/\(csv.lastPathComponent)",
                preferredStyle : .alert
            )

            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self?.present(alert, animated: true)
        }

        soakTest = sweep
        sweep.start()
    }

    /// presentDocumentPicker opens the Files picker on the original file, not a copy: PhotoImporter
    /// makes the app's own copy inside the security scope.
    private func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes : [.rawImage, .image],
            asCopy                 : false
        )
        picker.delegate = self

        present(picker, animated: true)
    }
}
