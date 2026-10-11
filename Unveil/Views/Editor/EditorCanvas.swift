//
//  EditorCanvas.swift
//  Unveil
//

import SwiftUI

/// EditorCanvas embeds the scene's single Metal view. SwiftUI updates only the photo identity
/// and tap action; textures, gestures and frame delivery remain owned by CanvasView.
struct EditorCanvas: UIViewRepresentable {

    let canvas     : CanvasView
    let photo      : PhotoID?
    let onSingleTap: () -> Void

    func makeUIView(context: Context) -> CanvasView {
        canvas
    }

    func updateUIView(
        _ view : CanvasView,
        context: Context
    ) {
        view.onSingleTap = onSingleTap

        if context.coordinator.shownPhoto != photo {
            context.coordinator.shownPhoto = photo
            view.resetZoom()
        }
    }

    static func dismantleUIView(
        _ view     : CanvasView,
        coordinator: Coordinator
    ) {
        view.onSingleTap = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {

        var shownPhoto: PhotoID?
    }
}
