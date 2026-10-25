import SwiftUI

struct AdvancedColorPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: AdvancedColorSession<Engine, Importer>
    @State private var tone = "shadows"
    @State private var dragging = false
    @GestureState private var wheelTouch = false
    @Environment(\.editorToolClose) private var close
    var title: String { session.pointColor ? "Point Color" : "Color Grading" }
    var prefix: String { session.pointColor ? "pointColor.\(session.selectedSample)." : "grading.\(tone)." }
    var body: some View {
        EditorToolPresentation(title: title, header: {
            Button("Undo", systemImage: "arrow.uturn.backward") { Task { await session.undo() } }
                .disabled(!session.model.canUndo || session.busy || dragging)
            Button("Redo", systemImage: "arrow.uturn.forward") { Task { await session.undo(redo: true) } }
                .disabled(!session.model.canRedo || session.busy || dragging)
            Button("Done") { close?() }.disabled(session.busy || dragging)
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if session.pointColor {
                        Button(session.picking ? "Cancel Sampling" : "Sample Color", systemImage: "eyedropper") { session.picking.toggle() }
                            .disabled(session.busy || dragging || !session.loaded || session.sampleCount >= 8)
                        Text(session.picking ? "Tap a color on the main photo. Pinch to zoom; use two fingers to pan." : "Sample up to eight colors, then adjust each color and its affected range.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if session.sampleCount > 0 {
                            Picker("Sample", selection: $session.selectedSample) {
                                ForEach(0..<session.sampleCount, id: \.self) { Text("Color \($0 + 1)").tag($0) }
                            }.disabled(session.busy || dragging)
                        }
                    } else {
                        Picker("Tone range", selection: $tone) {
                            Text("Shadows").tag("shadows"); Text("Midtones").tag("midtones")
                            Text("Highlights").tag("highlights"); Text("Global").tag("global")
                        }.disabled(session.busy || dragging)
                        wheel
                            .aspectRatio(1, contentMode: .fit).frame(maxWidth: 190)
                            .frame(maxWidth: .infinity).padding(.horizontal, 16)
                            .disabled(session.busy || !session.loaded)
                    }
                    rows(session.matching(prefix))
                    if !session.pointColor {
                        rows(session.controls.filter { $0.id == "grading.blending" || $0.id == "grading.balance" })
                    }
                    if !session.pointColor || session.sampleCount > 0 {
                        Button(session.pointColor ? "Reset Sample Adjustments" : "Reset This Wheel") { Task { await session.reset(prefix) } }
                        if session.pointColor {
                            Button("Delete Sample", role: .destructive) { Task { await session.deleteSample() } }
                        } else {
                            Button("Reset All Grading") { Task { await session.reset("grading.") } }
                        }
                    }
                    Text("Release a slider or wheel to apply one undoable edit.").font(.caption).foregroundStyle(.secondary)
                    if session.busy { ProgressView("Updating photo…") }
                    if let error = session.error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding(16)
            }
            .scrollDisabled(dragging)
            .task { await session.load() }
        }
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
    }
    private func rows(_ controls: [NativeDevelopControl]) -> some View {
        ForEach(controls) { control in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(control.label)
                    Spacer()
                    Text(session.values[control.id] ?? control.value, format: .number.precision(.fractionLength(control.step < 1 ? 1 : 0)))
                        .monospacedDigit()
                }
                Slider(value: Binding(get: { session.values[control.id] ?? control.value }, set: { session.setDraft(control.id, $0) }),
                       in: control.min...control.max, step: control.step) { active in
                    dragging = active
                    if !active { Task { await session.apply([control.id]) } }
                }
                .accessibilityLabel(control.label)
                .disabled(session.busy || !session.loaded)
                Button("Reset \(control.label)") {
                    session.setDraft(control.id, control.defaultValue)
                    Task { await session.apply([control.id]) }
                }.font(.caption).disabled(session.busy || dragging)
            }
        }
    }
    private var wheel: some View {
        GeometryReader { geometry in
            let radius = max(1, geometry.size.width / 2 - 10)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let hue = session.values[prefix + "hue"] ?? 0
            let sat = session.values[prefix + "sat"] ?? 0
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center)).padding(10)
                Circle().fill(RadialGradient(colors: [.white, .white.opacity(0)], center: .center, startRadius: 0, endRadius: radius)).padding(10)
                Circle().stroke(.black, lineWidth: 2).background(Circle().fill(.white))
                    .frame(width: 14, height: 14)
                    .position(x: center.x + cos(hue * .pi / 180) * sat / 100 * radius,
                              y: center.y + sin(hue * .pi / 180) * sat / 100 * radius)
            }
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($wheelTouch) { _, active, _ in active = true }
                .onChanged { value in
                    let dx = value.location.x - center.x, dy = value.location.y - center.y
                    let hue = (atan2(dy, dx) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                    dragging = true
                    session.setDraft(prefix + "hue", hue)
                    session.setDraft(prefix + "sat", min(100, hypot(dx, dy) / radius * 100))
                }.onEnded { _ in finishWheel() })
            .onChange(of: wheelTouch) { _, active in if !active && dragging { finishWheel() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(tone.capitalized) color wheel")
            .accessibilityHint("Use Hue and Saturation sliders below for precise adjustment")
        }
    }
    private func finishWheel() {
        dragging = false
        let ids = [prefix + "hue", prefix + "sat"]
        Task { await session.apply(ids) }
    }
}
