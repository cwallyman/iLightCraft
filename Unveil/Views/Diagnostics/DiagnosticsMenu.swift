//
//  DiagnosticsMenu.swift
//  Unveil
//

import SwiftUI

/// DiagnosticsMenu declares the system menu; command execution belongs to EditorDiagnostics.
struct DiagnosticsMenu<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {

    let diagnostics: EditorDiagnostics<Engine, Importer>
    let isPhotoOpen: Bool

    var body: some View {
        Menu("Diagnostics", systemImage: "ellipsis") {
            Button("Engine state", systemImage: "cpu") {
                Task { await diagnostics.showEngineState() }
            }

            Button(
                "Inject test frame",
                systemImage : "square.fill",
                action      : diagnostics.injectTestFrame
            )
            .disabled(isPhotoOpen)

            Button("Export reference images", systemImage: "square.and.arrow.down") {
                Task { await diagnostics.exportReferenceImages() }
            }

            Button(
                "Run Stress Test (10 min)",
                systemImage : "flame",
                action      : diagnostics.startSoakTest
            )
            .disabled(!isPhotoOpen)
        }
    }
}
