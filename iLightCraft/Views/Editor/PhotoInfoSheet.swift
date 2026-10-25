//
//  PhotoInfoSheet.swift
//  iLightCraft
//

import SwiftUI

/// PhotoInfoSheet lists what the app knows of the open photo: its name, file type and pixel size.
/// What is unknown (a type with no system name, a zero size) is left out.
struct PhotoInfoSheet: View {

    let name: String
    let type: String?
    let size: CGSize

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    private func closeTool() {
        if let closeDock { closeDock() } else { dismiss() }
    }

    var body: some View {
        EditorToolPresentation(title: "Info", header: {
            Button("Done", action: closeTool)
        }) {
            List {
                LabeledContent("Name", value: name)

                if let type {
                    LabeledContent("Type", value: type)
                }

                if size != .zero {
                    LabeledContent("Size", value: "\(Int(size.width)) × \(Int(size.height))")
                }
            }

        }
        .presentationDetents([.height(260)])
    }
}
