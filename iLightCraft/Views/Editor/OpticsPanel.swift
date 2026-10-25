import SwiftUI

struct OpticsPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: AdvancedColorSession<Engine, Importer>
    @State private var dragging = false
    @Environment(\.editorToolClose) private var close
    var body: some View {
        EditorToolPresentation(title: "Optics & Perspective", header: {
            Button("Undo", systemImage: "arrow.uturn.backward") { Task { await session.undo() } }
                .disabled(!session.model.canUndo || session.busy || dragging)
            Button("Redo", systemImage: "arrow.uturn.forward") { Task { await session.undo(redo: true) } }
                .disabled(!session.model.canRedo || session.busy || dragging)
            Button("Done") { close?() }.disabled(session.busy || dragging)
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Lens corrections").font(.headline)
                    Text(session.embeddedLens ? "Embedded lens correction data detected." : "No embedded lens correction data. Manual correction is available below.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Toggle("Use embedded lens corrections", isOn: Binding(get: { session.lensProfile }, set: { value in
                        Task { await session.option("optics", "lens_profile", value) }
                    })).disabled(!session.embeddedLens || session.busy)
                    Toggle("Remove chromatic aberration", isOn: Binding(get: { session.removeCA }, set: { value in
                        Task { await session.option("optics", "remove_ca", value) }
                    })).disabled(session.busy)
                    numericRows(session.matching("optics."))
                    Button("Reset Optics") { Task { await session.mutate("develop.resetSection", params: ["section": "optics"]) } }
                        .disabled(session.busy || dragging)
                    Divider()
                    Text("Perspective").font(.headline)
                    Text("Upright: \(session.upright.capitalized)").font(.subheadline)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())]) {
                        ForEach(["off", "auto", "level", "vertical", "full"], id: \.self) { mode in
                            Button(mode.capitalized) { Task { await session.setUpright(mode) } }
                        }
                        Button("Guided") { Task { await session.beginGuides() } }
                    }.buttonStyle(.bordered).disabled(session.busy || dragging)
                    if session.guiding {
                        Text("Draw 2–4 lines on the main photo along edges that should be horizontal or vertical. Pinch to zoom; pan with two fingers.")
                            .font(.footnote)
                        Text("\(session.guideLines.count) guides")
                        Button("Apply Guides") { Task { await session.applyGuides() } }
                            .disabled(session.busy || session.guideLines.count < 2)
                        Button("Clear Guides") { session.guideLines = []; session.guideStroke = [] }
                        Button("Cancel Guides") { session.guiding = false; session.guideLines = []; session.guideStroke = [] }
                    }
                    Toggle("Constrain crop", isOn: Binding(get: { session.constrainCrop }, set: { value in
                        Task { await session.option("geometry", "constrain_crop", value) }
                    })).disabled(session.busy)
                    numericRows(session.matching("geometry."))
                    Button("Reset Perspective") { Task { await session.mutate("develop.resetSection", params: ["section": "geometry"]) } }
                        .disabled(session.busy || dragging)
                    Text("Release a slider to apply. Lens coverage depends on correction data embedded in the photo; external lens-profile selection is not available.")
                        .font(.caption).foregroundStyle(.secondary)
                    if session.busy { ProgressView("Updating photo…") }
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(16)
            }
            .scrollDisabled(dragging)
            .task { await session.load() }
        }
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
    }
    private func numericRows(_ controls: [NativeDevelopControl]) -> some View {
        ForEach(controls) { control in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(control.label); Spacer()
                    Text(session.values[control.id] ?? control.value, format: .number.precision(.fractionLength(control.step < 1 ? 1 : 0)))
                        .monospacedDigit()
                }
                Slider(value: Binding(get: { session.values[control.id] ?? control.value }, set: { session.setDraft(control.id, $0) }),
                       in: control.min...control.max, step: control.step) { active in
                    dragging = active
                    if !active { Task { await session.apply([control.id]) } }
                }.accessibilityLabel(control.label).disabled(session.busy || !session.loaded)
            }
        }
    }
}
