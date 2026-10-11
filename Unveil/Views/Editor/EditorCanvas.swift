//
//  EditorCanvas.swift
//  Unveil
//

import SwiftUI

/// EditorCanvas embeds the scene's single Metal view. SwiftUI updates only the photo identity and
/// size and the tap and zoom callbacks; textures, gestures and frame delivery remain owned by CanvasView.
struct EditorCanvas: UIViewRepresentable {

    let canvas      : CanvasView
    let photo       : PhotoID?
    let photoSize   : CGSize
    let onSingleTap : () -> Void
    let onTouchDown : (() -> Void)?
    let onZoomChange: (Int) -> Void

    func makeUIView(context: Context) -> CanvasView {
        canvas
    }

    func updateUIView(
        _ view : CanvasView,
        context: Context
    ) {
        view.onSingleTap  = onSingleTap
        view.onTouchDown  = onTouchDown
        view.onZoomChange = onZoomChange
        view.photoSize    = photoSize

        if context.coordinator.shownPhoto != photo {
            context.coordinator.shownPhoto = photo
            view.resetZoom()
        }
    }

    static func dismantleUIView(
        _ view     : CanvasView,
        coordinator: Coordinator
    ) {
        view.onSingleTap  = nil
        view.onTouchDown  = nil
        view.onZoomChange = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {

        var shownPhoto: PhotoID?
    }
}
