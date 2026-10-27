//
//  DiagnosticsMenuItems.swift
//  iLightCraft
//

import SwiftUI

/// DiagnosticsMenuItems declares the Debug items of the editor's ellipsis menu; command
/// execution belongs to EditorDiagnostics.
struct DiagnosticsMenuItems<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {

    let diagnostics: EditorDiagnostics<Engine, Importer>
    let isPhotoOpen: Bool

    var body: some View {
        Section("Diagnostics") {
            Button("Engine state", lightCraftIcon: "LightCraft-Monitor") {
                Task { await diagnostics.showEngineState() }
            }

            Button(
                "Inject test frame",
                lightCraftIcon : "LightCraft-Single",
                action      : diagnostics.injectTestFrame
            )
            .disabled(isPhotoOpen)

            Button("Export reference images", lightCraftIcon: "LightCraft-Share") {
                Task { await diagnostics.exportReferenceImages() }
            }

            Button("Clean Up Test Data", lightCraftIcon: "LightCraft-Trash") {
                Task { await diagnostics.cleanUpTestData() }
            }

            Button(
                "Run Stress Test (10 min)",
                lightCraftIcon : "LightCraft-Activity",
                action      : diagnostics.startSoakTest
            )
            .disabled(!isPhotoOpen)
        }
    }
}
