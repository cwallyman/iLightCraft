//
//  LensBlurPanel.swift
//  Unveil
//

import SwiftUI

/// LensBlurPanel exposes an optional local depth model and explicit copy-based rendering.
struct LensBlurPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: LensBlurSession<Engine, Importer>
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Depth estimation runs locally using Depth Anything V2 Small. This first implementation creates a rendered TIFF copy; return to the source to change the blur. It does not overwrite a Photos item.")
                .font(.footnote).foregroundStyle(.secondary)
            if !session.installed {
                if let url = URL(string: DepthModelStore.modelPage) { Link("Model and Apache-2.0 license", destination: url) }
                Text("Download approximately 50 MB once. By downloading, you accept the linked Apache-2.0 terms. No photos are sent to the download host.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Download On-device Depth Model", action: session.download)
                    .buttonStyle(.borderedProminent).disabled(session.busy)
            } else {
                Text("Blur amount: \(session.amount, specifier: "%.0f")")
                Slider(value: $session.amount, in: 0...100, step: 1).accessibilityLabel("Blur amount")
                Text("Relative focus: \(session.focus, specifier: "%.2f")")
                Slider(value: $session.focus, in: 0...1, step: 0.01).accessibilityLabel("Relative focus")
                Text("In-focus range: \(session.range, specifier: "%.2f")")
                Slider(value: $session.range, in: 0...0.9, step: 0.01).accessibilityLabel("In-focus range")
                Text("Focus is relative model depth, not meters. Bokeh shape and painted depth refinement are not implemented.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Create Blurred Copy", action: session.render).buttonStyle(.borderedProminent).disabled(session.busy)
                Button("Remove Downloaded Model", role: .destructive, action: session.removeModel).disabled(session.busy)
            }
            if session.busy {
                ProgressView(session.status)
                Button("Cancel After Current Stage", action: session.cancel)
            } else if !session.status.isEmpty { Text(session.status).font(.footnote) }
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }
}
