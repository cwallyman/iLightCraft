//
//  EnhancementPanel.swift
//  iLightCraft
//

import SwiftUI

/// EnhancementPanel distinguishes RGB AI restoration from unavailable sensor-domain Raw Details.
struct EnhancementPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: EnhancementSession<Engine, Importer>
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Enhancement", selection: $session.mode) {
                Text("AI RGB Denoise").tag(EnhancementModel.denoise)
                Text("AI Super Resolution (2×)").tag(EnhancementModel.superResolution)
            }.disabled(session.busy)
            Text("Real-ESRGAN RGB restoration runs on this device and creates an opaque 8-bit SDR PNG copy. Denoise retains image dimensions; Super Resolution doubles each dimension. This does not change or re-demosaic sensor RAW data.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Raw Details and sensor-domain AI denoise still need a compatible permissive model and a sensor-data pipeline. They are not substituted with sharpening or ordinary resizing.")
                .font(.caption).foregroundStyle(.secondary)
            if let link = URL(string: EnhancementModel.source) { Link("Model publisher and BSD-3-Clause terms", destination: link) }
            if session.installed.contains(session.mode) {
                Button("Create Enhanced Copy", action: session.render).buttonStyle(.borderedProminent).disabled(session.busy)
                Button("Remove Downloaded Model", role: .destructive, action: session.removeModel).disabled(session.busy)
            } else {
                Text("Optional download: approximately 2.3 MB. By downloading, you accept the linked BSD-3-Clause terms. No photo is sent to the download host.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Download On-device Model", action: session.download).buttonStyle(.borderedProminent).disabled(session.busy)
            }
            if session.busy {
                ProgressView(value: session.progress)
                Text(session.status).font(.footnote)
                Button("Cancel Processing", action: session.cancel)
            } else if !session.status.isEmpty { Text(session.status).font(.footnote) }
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }
}
