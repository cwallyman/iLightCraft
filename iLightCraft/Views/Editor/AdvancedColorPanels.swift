import SwiftUI

struct AdvancedColorPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: AdvancedColorSession<Engine, Importer>
    @State private var tone = "midtones"
    @State private var activeWheel: String?
    @State private var dragging = false
    @GestureState private var wheelTouch = false
    @Environment(\.editorToolClose) private var close
    var title: String { session.pointColor ? "Point Color" : "Color Grading" }
    var prefix: String { session.pointColor ? "pointColor.\(session.selectedSample)." : "grading.\(tone)." }
    var body: some View {
        EditorToolPresentation(title: title, header: { EmptyView() }) {
            EditorPanelScroll {
                VStack(alignment: .leading, spacing: 16) {
                    if session.pointColor {
                        Button(session.picking ? "Cancel Sampling" : "Sample Color", lightCraftIcon: "LightCraft-Picker") { session.picking.toggle() }
                            .disabled(session.busy || dragging || !session.loaded || session.sampleCount >= 8)
                        Text(session.picking ? "Tap a color on the main photo. Pinch to zoom; use two fingers to pan." : "Sample up to eight colors, then adjust each color and its affected range.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if session.sampleCount > 0 {
                            Picker("Sample", selection: $session.selectedSample) {
                                ForEach(0..<session.sampleCount, id: \.self) { Text("Color \($0 + 1)").tag($0) }
                            }.disabled(session.busy || dragging)
                        }
                        rows(session.matching(prefix))
                    } else {
                        gradingLayout
                    }
                    if session.pointColor && session.sampleCount > 0 {
                        Button(session.pointColor ? "Reset Sample Adjustments" : "Reset This Wheel") { Task { await session.reset(prefix) } }
                        if session.pointColor {
                            Button("Delete Sample", role: .destructive) { Task { await session.deleteSample() } }
                        } else {
                            Button("Reset All Grading") { Task { await session.reset("grading.") } }
                        }
                    }
                    if session.pointColor {
                        Text("Release a slider or wheel to apply one undoable edit.").font(.caption).foregroundStyle(.secondary)
                    }
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
                    LightCraftNumberButton(title: control.label, value: session.values[control.id] ?? control.value,
                                           range: control.min...control.max, step: control.step, decimals: control.step < 1 ? 2 : 0) { number in
                        session.setDraft(control.id, number)
                        Task { await session.apply([control.id]) }
                    }.disabled(session.busy || !session.loaded)
                }.foregroundStyle(LightCraftPanelStyle.isChanged(session.values[control.id] ?? control.value, from: control.defaultValue) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSlider(value: Binding(get: { session.values[control.id] ?? control.value }, set: { session.setDraft(control.id, $0) }),
                       in: control.min...control.max, step: control.step, controlID: control.id, defaultValue: control.defaultValue) { active in
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
    /// gradingLayout shows the three tone wheels together, Midtones above Shadows and Highlights,
    /// then their luminance, Blending and Balance. Tapping a wheel selects it for fine tuning.
    private var gradingLayout: some View {
        VStack(spacing: 18) {
            wheelCell("midtones", size: 120)
            HStack(alignment: .top) {
                wheelCell("shadows", size: 120)
                Spacer(minLength: 8)
                wheelCell("highlights", size: 120)
            }
            VStack(spacing: 12) {
                ForEach(["shadows", "midtones", "highlights"], id: \.self) { tone in
                    compactRow("grading.\(tone).lum", label: "\(tone.capitalized) Luminance")
                }
                compactRow("grading.blending", label: "Blending")
                compactRow("grading.balance", label: "Balance")
            }
            DisclosureGroup {
                VStack(spacing: 12) {
                    compactRow("grading.\(tone).hue", label: "Hue")
                    compactRow("grading.\(tone).sat", label: "Saturation")
                }.padding(.top, 8)
            } label: {
                Text("Fine Tune \(tone.capitalized)").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.white)
            }
            DisclosureGroup {
                VStack(spacing: 12) {
                    wheelCell("global", size: 120)
                    compactRow("grading.global.lum", label: "Global Luminance")
                }.padding(.top, 8)
            } label: {
                Text("Global").font(.system(size: 16, weight: .bold)).foregroundStyle(Color.white)
            }
            ViewThatFits(in: .horizontal) {
                HStack {
                    Button("Reset \(tone.capitalized)") { Task { await session.reset("grading.\(tone).") } }
                    Spacer()
                    Button("Reset All Grading") { Task { await session.reset("grading.") } }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Button("Reset \(tone.capitalized)") { Task { await session.reset("grading.\(tone).") } }
                    Button("Reset All Grading") { Task { await session.reset("grading.") } }
                }
            }
            .font(.footnote.weight(.semibold))
            .disabled(session.busy || dragging)
        }
    }

    private func wheelCell(_ tone: String, size: CGFloat) -> some View {
        VStack(spacing: 6) {
            // Wheels shrink with the panel, up to their full size.
            wheel(tone).aspectRatio(1, contentMode: .fit).frame(maxWidth: size)
                .disabled(session.busy || !session.loaded)
            Text(tone.capitalized).font(.footnote.weight(.semibold))
                .foregroundStyle(self.tone == tone ? LightCraftPanelStyle.highlight : LightCraftPanelStyle.label)
        }
    }

    /// compactRow is one grading slider without a reset button; reset sits in its context menu.
    @ViewBuilder private func compactRow(_ id: String, label: String) -> some View {
        if let control = session.controls.first(where: { $0.id == id }) {
            let value = session.values[id] ?? control.value
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer()
                    LightCraftNumberButton(title: label, value: value,
                                           range: control.min...control.max, step: control.step, decimals: control.step < 1 ? 2 : 0) { number in
                        session.setDraft(id, number)
                        Task { await session.apply([id]) }
                    }.disabled(session.busy || !session.loaded)
                }.foregroundStyle(LightCraftPanelStyle.isChanged(value, from: control.defaultValue) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSlider(value: Binding(get: { session.values[id] ?? control.value }, set: { session.setDraft(id, $0) }),
                       in: control.min...control.max, step: control.step, controlID: id, defaultValue: control.defaultValue) { active in
                    dragging = active
                    if !active { Task { await session.apply([id]) } }
                }
                .accessibilityLabel(label)
                .disabled(session.busy || !session.loaded)
            }
            .contextMenu {
                Button("Reset \(label)") {
                    session.setDraft(id, control.defaultValue)
                    Task { await session.apply([id]) }
                }
            }
        }
    }

    private func wheel(_ wheelTone: String) -> some View {
        let wheelPrefix = "grading.\(wheelTone)."
        return GeometryReader { geometry in
            let radius = max(1, geometry.size.width / 2 - 10)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let hue = session.values[wheelPrefix + "hue"] ?? 0
            let sat = session.values[wheelPrefix + "sat"] ?? 0
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
                    tone = wheelTone; activeWheel = wheelTone
                    session.setDraft(wheelPrefix + "hue", hue)
                    session.setDraft(wheelPrefix + "sat", min(100, hypot(dx, dy) / radius * 100))
                }.onEnded { _ in finishWheel() })
            .onChange(of: wheelTouch) { _, active in if !active && dragging && activeWheel == wheelTone { finishWheel() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(wheelTone.capitalized) color wheel")
            .accessibilityHint("Use Hue and Saturation sliders below for precise adjustment")
        }
    }
    private func finishWheel() {
        guard let wheel = activeWheel else { dragging = false; return }
        dragging = false; activeWheel = nil
        let ids = ["grading.\(wheel).hue", "grading.\(wheel).sat"]
        Task { await session.apply(ids) }
    }
}
