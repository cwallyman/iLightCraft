//
//  ZoomPill.swift
//  Unveil
//

import SwiftUI

/// ZoomPill shows the canvas zoom and offers the zoom presets. It is its own view, so a zoom
/// update re-evaluates only this label and not the whole editor.
struct ZoomPill<Engine: EngineDriving, Importer: PhotoImporting, LibraryLoader: PhotoLibraryLoading>: View {

    let session: EditorSession<Engine, Importer, LibraryLoader>
    let canvas : CanvasView

    var body: some View {
        Menu {
            Button("Zoom to Fit", action: canvas.zoomToFit)

            Button("100%") { canvas.zoom(toPercent: 100) }

            Button("200%") { canvas.zoom(toPercent: 200) }
        } label: {
            Text("\(session.zoomPercent)%")
                .monospacedDigit()
        }
        .accessibilityLabel("Zoom")
        .accessibilityValue("\(session.zoomPercent)%")
        .accessibilityIdentifier("zoom-pill")
    }
}
