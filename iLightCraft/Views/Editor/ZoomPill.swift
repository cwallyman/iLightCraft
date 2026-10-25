//
//  ZoomPill.swift
//  iLightCraft
//

import SwiftUI

/// ZoomPill shows the canvas zoom and offers the zoom presets. It is its own view, so a zoom
/// update re-evaluates only this label and not the whole editor. The keyboard shortcuts live in
/// ZoomCommands, at scene level: a closed toolbar menu registers none of its items' shortcuts.
struct ZoomPill<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting, LibraryLoader: PhotoLibraryLoading>: View {

    let session: EditorSession<Engine, Importer, LibraryLoader>
    let canvas : CanvasView

    var body: some View {
        let label = "\(ZoomScale.label(forPercent: session.zoomPercent))%"

        Menu {
            Button("Zoom In", systemImage: "plus.magnifyingglass", action: canvas.zoomIn)

            Button("Zoom Out", systemImage: "minus.magnifyingglass", action: canvas.zoomOut)

            Divider()

            Button("Zoom to Fit", action: canvas.zoomToFit)

            Button("Fill Screen", action: canvas.zoomToFill)

            Button("Actual Size") { canvas.zoom(toPercent: 100) }

            Button("200%") { canvas.zoom(toPercent: 200) }
        } label: {
            Text(label)
                .monospacedDigit()
        }
        .accessibilityLabel("Zoom")
        .accessibilityValue(label)
        .accessibilityIdentifier("zoom-pill")
    }
}
