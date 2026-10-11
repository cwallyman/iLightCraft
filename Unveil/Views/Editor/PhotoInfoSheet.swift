//
//  PhotoInfoSheet.swift
//  Unveil
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

    var body: some View {
        NavigationStack {
            List {
                LabeledContent("Name", value: name)

                if let type {
                    LabeledContent("Type", value: type)
                }

                if size != .zero {
                    LabeledContent("Size", value: "\(Int(size.width)) × \(Int(size.height))")
                }
            }
            .navigationTitle("Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Done", action: dismiss.callAsFunction)
            }
        }
        .presentationDetents([.height(260)])
    }
}
