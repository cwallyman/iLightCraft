//
//  EditorCanvas.swift
//  Unveil
//

import SwiftUI

/// EditorCanvas embeds the scene's single Metal view. SwiftUI updates only the photo identity and
/// size, the clipping overlay, the before look and the tap, hold, zoom and window callbacks;
/// textures, gestures and frame delivery remain owned by CanvasView.
struct EditorCanvas: UIViewRepresentable {

    let canvas         : CanvasView
    let photo          : PhotoID?
    let photoSize      : CGSize
    let clipping       : ClippingOverlay
    let isShowingBefore: Bool
    let onSingleTap    : () -> Void
    let onTouchDown    : (() -> Void)?
    let onHoldChange   : (Bool) -> Void
    let onToggleBefore : () -> Void
    let onZoomChange   : (Double) -> Void
    let onWindowChange : (FrameWindow?, _ isDraft: Bool) -> Void

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

        view.onHoldChange    = onHoldChange
        view.onToggleBefore  = onToggleBefore
        view.isShowingBefore = isShowingBefore

        view.clippingOverlay = clipping

        view.onVisibleWindowChange = onWindowChange

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

        view.onHoldChange   = nil
        view.onToggleBefore = nil

        view.onVisibleWindowChange = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {

        var shownPhoto: PhotoID?
    }
}
