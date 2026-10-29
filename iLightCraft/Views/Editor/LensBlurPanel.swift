//
//  LensBlurPanel.swift
//  iLightCraft
//

import SwiftUI

/// LensBlurPanel renders a separate copy using the on-device depth model.
struct LensBlurPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: LensBlurSession<Engine, Importer>
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !session.installed {
                Text("The bundled depth model is unavailable. Rebuild the app with its model resources.")
                    .font(.footnote).foregroundStyle(LightCraftPanelStyle.text)
            } else {
                LightCraftSliderRow("Blur Amount", value: $session.amount, in: 0...100, defaultValue: 25, step: 1)
                LightCraftSliderRow("Relative Focus", value: $session.focus, in: 0...1, defaultValue: 0.5, step: 0.01)
                LightCraftSliderRow("In-Focus Range", value: $session.range, in: 0...0.9, defaultValue: 0.15, step: 0.01)
                Button(action: session.render) {
                    Text("Create Blurred Copy").font(.body.weight(.semibold))
                        .foregroundStyle(Color.black)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Color(red: 242.0 / 255, green: 165.0 / 255, blue: 22.0 / 255), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).disabled(session.busy).opacity(session.busy ? 0.5 : 1)
            }
            if session.busy {
                ProgressView(session.status)
                Button("Cancel After Current Stage", action: session.cancel)
            } else if !session.status.isEmpty { Text(session.status).font(.footnote) }
            if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }
}
