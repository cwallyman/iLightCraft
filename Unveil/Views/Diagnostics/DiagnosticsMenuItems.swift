//
//  DiagnosticsMenuItems.swift
//  Unveil
//

import SwiftUI

/// DiagnosticsMenuItems declares the Debug items of the editor's ellipsis menu; command
/// execution belongs to EditorDiagnostics.
struct DiagnosticsMenuItems<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {

    let diagnostics: EditorDiagnostics<Engine, Importer>
    let isPhotoOpen: Bool

    var body: some View {
        Section("Diagnostics") {
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

            Button("Clean Up Test Data", systemImage: "trash") {
                Task { await diagnostics.cleanUpTestData() }
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
