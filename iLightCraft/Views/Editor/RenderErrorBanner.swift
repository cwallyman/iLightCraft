//
//  RenderErrorBanner.swift
//  iLightCraft
//

import SwiftUI

/// RenderErrorBanner tells, without blocking, that the last preview could not be rendered: the
/// canvas still shows the last good frame and editing goes on. The close button dismisses it.
struct RenderErrorBanner: View {

    let message  : String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(lightCraftIcon: "LightCraft-Info")
                .foregroundStyle(.yellow)
                .accessibilityHidden(true)

            Text(message)
                .font(.callout)
                .lineLimit(3)

            Button("Dismiss", lightCraftIcon: "LightCraft-Close", action: onDismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .accessibilityIdentifier("render-error-dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .capsule)
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("render-error-banner")
    }
}
