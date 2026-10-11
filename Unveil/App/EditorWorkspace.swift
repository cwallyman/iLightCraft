//
//  EditorWorkspace.swift
//  Unveil
//

import Metal
import UIKit

/// EditorWorkspace composes one scene's editor and native canvas. It also refreshes the preview
/// after activation; the task runs after EngineLifecycleObserver's synchronous resume callback.
@MainActor
final class EditorWorkspace {

    let session    : EditorSession<EngineManager, PhotoImporter, PhotoLibraryLoader>
    let canvas     : CanvasView
    let diagnostics: EditorDiagnostics<EngineManager, PhotoImporter>

    private let launchRunner = EditorLaunchRunner()

    // Foundation exposes notification tokens as an existential.
    private var becomeActiveToken: (any NSObjectProtocol)?

    init(
        engine       : EngineManager,
        device       : some MTLDevice,
        previewPixels: Int
    ) {
        let viewModel = EditorViewModel(
            engine        : engine,
            importer      : PhotoImporter(),
            previewPixels : previewPixels
        )
        let session = EditorSession(viewModel: viewModel, libraryLoader: PhotoLibraryLoader())
        let canvas  = CanvasView(frames: engine.frames, device: device)

        self.session = session
        self.canvas  = canvas
        diagnostics  = EditorDiagnostics(
            engine            : engine,
            viewModel         : viewModel,
            possibleTearCount : { [weak canvas] in canvas?.possibleTearCount ?? 0 },
            present           : { [weak session] in session?.alert = $0 }
        )

        becomeActiveToken = NotificationCenter.default.addObserver(
            forName : UIApplication.didBecomeActiveNotification,
            object  : nil,
            queue   : nil
        ) { _ in
            Task { @MainActor in await viewModel.refreshPreview() }
        }

        launchRunner.start(
            engine    : engine,
            viewModel : viewModel,
            showPanel : { [weak session] group in session?.showPanel(group) }
        )
    }

    isolated deinit {
        if let becomeActiveToken {
            NotificationCenter.default.removeObserver(becomeActiveToken)
        }
    }
}
