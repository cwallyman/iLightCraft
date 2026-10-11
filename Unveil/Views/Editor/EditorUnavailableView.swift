//
//  EditorUnavailableView.swift
//  Unveil
//

import SwiftUI

struct EditorUnavailableView: View {

    let reason: String

    var body: some View {
        ContentUnavailableView(
            "Unable to Start Editor",
            systemImage : "exclamationmark.triangle",
            description : Text(reason)
        )
    }
}
