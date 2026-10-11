//
//  AdjustmentPanel.swift
//  Unveil
//

import SwiftUI

/// AdjustmentPanel lists the sliders of one AdjustmentGroup and turns each slider gesture into the
/// view model's begin, drag and end calls.
///
/// The sliders stay disabled until a photo is open: there is nothing for the engine to apply them to.
/// Drags start with `Task.immediate`, so each call runs its synchronous part (clamp, record, queue)
/// right away, in the order SwiftUI delivered the values. A plain `Task` would only be scheduled,
/// and the release could then queue its full preview ahead of the last drag value.
struct AdjustmentPanel<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>
    let group    : AdjustmentGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            ForEach(group.kinds, id: \.self) { kind in
                AdjustmentSlider(
                    kind             : kind,
                    value            : binding(for: kind),
                    defaultValue     : viewModel.defaultValue(of: kind),
                    onEditingChanged : { editingChanged(kind, isEditing: $0) },
                    onCommit         : { commit(kind, to: $0) },
                    onReset          : { Task.immediate { await viewModel.reset(kind) } }
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .disabled(!viewModel.isPhotoOpen)
    }

    /// binding reads the model's value for `kind` and sends every new slider value as a drag.
    private func binding(for kind: DevelopAdjustmentKind) -> Binding<Double> {
        Binding(
            get: { viewModel.values[kind] ?? kind.defaultValue },
            set: { newValue in Task.immediate { await viewModel.drag(kind, to: newValue) } }
        )
    }

    /// commit runs one discrete change (a stepper press, a VoiceOver step) as a whole edit:
    /// set the value, then a full preview. Each one is final, so it must not stop on a draft frame.
    private func commit(
        _ kind     : DevelopAdjustmentKind,
        to newValue: Double
    ) {
        Task.immediate {
            viewModel.beginDrag(kind)
            await viewModel.drag(kind, to: newValue)
            await viewModel.endDrag(kind)
        }
    }

    private func editingChanged(
        _ kind   : DevelopAdjustmentKind,
        isEditing: Bool
    ) {
        if isEditing {
            viewModel.beginDrag(kind)
        } else {
            Task.immediate { await viewModel.endDrag(kind) }
        }
    }
}
