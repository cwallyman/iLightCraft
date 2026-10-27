//
//  BeforeEditedComparison.swift
//  iLightCraft
//

import SwiftUI

/// BeforeEditedComparison shows matching engine before/after previews of the same photo.
struct BeforeEditedComparison<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PhotoPanelSession<Engine, Importer>
    let tool: EditorDockTool?
    let zoomRequest: PhotoToolViewport.ZoomRequest?
    let onZoomPercent: (Double) -> Void
    let onInteraction: (Bool) -> Void
    private struct RefreshKey: Equatable {
        let photo: PhotoID?
        let edit: EditSnapshot?
        let tool: EditorDockTool?
    }
    var body: some View {
        Group {
            if let error = session.comparisonError {
                VStack(spacing: 12) {
                    Text(error).foregroundStyle(.red)
                    Button("Retry", action: session.requestComparison).buttonStyle(.bordered)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let before = session.beforeImage, let edited = session.editedImage {
                HStack(spacing: 8) {
                    pane("Before", image: before)
                    pane("Edited", image: edited)
                }
                .overlay(alignment: .topTrailing) { if session.comparisonLoading { ProgressView().padding(8) } }
            } else {
                ProgressView("Preparing comparison…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8).background(EditorSurround.color)
        .task(id: RefreshKey(photo: session.model.openPhoto, edit: session.model.undoStack.last, tool: tool)) { session.requestComparison() }
        .onDisappear { session.stopComparison() }
        .accessibilityIdentifier("before-edited-comparison")
    }
    private func pane(_ title: String, image: UIImage) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.text)
            PhotoToolViewport(image: image, mode: .masks, zoomRequest: zoomRequest,
                              onInteraction: onInteraction, sourcePixelWidth: session.model.photoSize.width,
                              onZoomPercent: onZoomPercent)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
