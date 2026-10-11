//
//  AdjustCard.swift
//  Unveil
//

import SwiftUI

/// AdjustCard is the glass container left of the tool rail. For now it holds the group picker and
/// the existing sliders of the selected group; the carousel card replaces it.
struct AdjustCard<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>

    @Binding
    var group: AdjustmentGroup

    var body: some View {
        VStack(spacing: 0) {

            Picker("Group", selection: $group) {

                ForEach(AdjustmentGroup.allCases) { group in
                    Text(group.title)
                        .tag(group)
                }
            }
            .pickerStyle(.menu)
            .padding(.top, 12)

            ScrollView {
                AdjustmentPanel(viewModel: viewModel, group: group)
            }
        }
        .frame(width: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Adjustments")
    }
}
