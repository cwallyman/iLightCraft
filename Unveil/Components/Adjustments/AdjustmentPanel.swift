//
//  AdjustmentPanel.swift
//  Unveil
//

import SwiftUI

/// AdjustmentPanel lists the ten develop sliders, grouped as Luce and Colore, and turns each slider gesture into the view
/// model's begin, drag and end calls.
///
/// The sliders stay disabled until a photo is open: there is nothing for the engine to apply them to.
/// Drags start with `Task.immediate`, so each call runs its synchronous part (clamp, record, queue)
/// right away, in the order SwiftUI delivered the values. A plain `Task` would only be scheduled,
/// and the release could then queue its full preview ahead of the last drag value.
struct AdjustmentPanel<Engine: EngineDriving, Importer: PhotoImporting>: View {

    let viewModel: EditorViewModel<Engine, Importer>

    private static var lightKinds: [DevelopAdjustmentKind] {
        [.exposure, .contrast, .highlights, .shadows, .whites, .blacks]
    }

    private static var colorKinds: [DevelopAdjustmentKind] {
        [.temperature, .tint, .vibrance, .saturation]
    }

    var body: some View {
        ScrollView {

            VStack(alignment: .leading, spacing: 20) {

                group("Luce", kinds: Self.lightKinds)

                group("Colore", kinds: Self.colorKinds)
            }
            .padding(20)
        }
        .disabled(!viewModel.isPhotoOpen)
    }

    private func group(
        _ title: String,
        kinds  : [DevelopAdjustmentKind]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {

            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(kinds, id: \.self) { kind in
                AdjustmentSlider(
                    kind                  : kind,
                    value                 : binding(for: kind),
                    onEditingChanged      : { editingChanged(kind, isEditing: $0) },
                    onAccessibilityAdjust : { accessibilityAdjust(kind, to: $0) },
                    onReset               : { accessibilityAdjust(kind, to: kind.defaultValue) }
                )
            }
        }
    }

    /// binding reads the model's value for `kind` and sends every new slider value as a drag.
    private func binding(for kind: DevelopAdjustmentKind) -> Binding<Double> {
        Binding(
            get: { viewModel.values[kind] ?? kind.defaultValue },
            set: { newValue in Task.immediate { await viewModel.drag(kind, to: newValue) } }
        )
    }

    /// accessibilityAdjust runs one VoiceOver step, or a double-tap reset, as a whole edit: set the value, then a full
    /// preview. Each step is final, so it must not stop on a draft frame.
    private func accessibilityAdjust(
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
