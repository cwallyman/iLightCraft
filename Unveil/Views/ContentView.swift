//
//  ContentView.swift
//  Unveil
//

import Metal
import SwiftUI

/// ContentView is the scene's root. It composes the editor after launch and initial layout,
/// keeping that workspace in State so body updates never create another engine or canvas.
struct ContentView: View {

    let appDelegate: AppDelegate

    @Environment(\.displayScale)
    private var displayScale

    @State
    private var workspace: EditorWorkspace?

    @State
    private var startupError: String?

    var body: some View {
        
        GeometryReader { geometry in
            
            Group {
                if let workspace {
                    EditorView(
                        session     : workspace.session,
                        canvas      : workspace.canvas,
                        diagnostics : workspace.diagnostics
                    )
                
                } else if let startupError {
                    EditorUnavailableView(reason: startupError)
                
                } else {
                    ProgressView("Starting Editor")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                
            }
            .task(id: geometry.size) {
                prepareEditor(size: geometry.size)
            }
        }
    }

    /// prepareEditor samples the window's initial pixel size once. The engine owns a fixed
    /// preview pool, and resizing the window must not rebuild that pool or the editor session.
    private func prepareEditor(size: CGSize) {
        guard workspace == nil, startupError == nil,
              size.width > 0, size.height > 0
        else { return }

        guard let engine = appDelegate.engine else {
            showStartupError(appDelegate.engineError?.message ?? "The engine did not start.")
            return
        }

        guard let device = MTLCreateSystemDefaultDevice() else {
            showStartupError("This device has no Metal GPU.")
            return
        }

        let longEdge = Int(max(size.width, size.height) * displayScale)
        workspace = EditorWorkspace(
            engine        : engine,
            device        : device,
            previewPixels : min(max(longEdge, 1), AppDelegate.maximumPreviewPixels)
        )
    }

    private func showStartupError(_ reason: String) {
        startupError = reason
        EditorLaunchRunner.exitIfAgentDriven(reason: reason)
    }
}
