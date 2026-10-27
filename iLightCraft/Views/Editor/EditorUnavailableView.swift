//
//  EditorUnavailableView.swift
//  iLightCraft
//

import SwiftUI

struct EditorUnavailableView: View {

    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label("Unable to Start Editor", lightCraftIcon: "LightCraft-Info")
        } description: {
            Text(reason)
        }
    }
}
