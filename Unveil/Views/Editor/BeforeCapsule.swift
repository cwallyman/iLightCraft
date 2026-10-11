//
//  BeforeCapsule.swift
//  Unveil
//

import SwiftUI

/// BeforeCapsule is the small glass label at the top centre of the canvas while the unedited look
/// shows. It takes no touches, so the finger that holds the canvas keeps holding it, and VoiceOver
/// reads it as a status, not as a control.
struct BeforeCapsule: View {

    var body: some View {
        Text("Before")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: .capsule)
            .padding(.top, 12)
            .allowsHitTesting(false)
            .accessibilityLabel("Showing the original")
            .accessibilityIdentifier("before-capsule")
    }
}
