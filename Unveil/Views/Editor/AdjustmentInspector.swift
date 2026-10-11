//
//  AdjustmentInspector.swift
//  Unveil
//

import SwiftUI

/// AdjustmentInspector puts the existing sliders in a native, scrolling form. Its group picker
/// uses system presentation and accessibility; SwiftUI's inspector adapts the presentation.
struct AdjustmentInspector<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>

    @Bindable
    private var selection: AdjustmentInspectorState

    init(
        viewModel: EditorViewModel<Engine, Importer>,
        selection: AdjustmentInspectorState
    ) {
        self.viewModel = viewModel
        self.selection = selection
    }

    var body: some View {
        Form {

            Picker("Group", selection: $selection.selectedGroup) {

                ForEach(AdjustmentGroup.allCases) { group in
                    Text(group.title)
                        .tag(group)
                }
            }
            .pickerStyle(.menu)

            Section(selection.selectedGroup.title) {

                AdjustmentPanel(viewModel: viewModel, group: selection.selectedGroup)
                    .listRowInsets(EdgeInsets())
            }
        }
        .disabled(!viewModel.isPhotoOpen)
    }
}
