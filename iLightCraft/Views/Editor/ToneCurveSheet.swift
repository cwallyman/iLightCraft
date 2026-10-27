import SwiftUI
import UniformTypeIdentifiers

struct ToneCurveSheet<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: ToneCurveSession<Engine, Importer>
    @State private var dragging = false
    @State private var savingPreset = false
    @State private var presetName = ""
    @State private var importingPresets = false
    @State private var sharingPresets = false
    @State private var exportedPresets: URL?
    @GestureState private var graphTouchActive = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    private func closeTool() {
        if let closeDock { closeDock() } else { dismiss() }
    }

    init(model: EditorViewModel<Engine, Importer>) {
        _session = State(initialValue: ToneCurveSession(model: model))
    }

    private var curveColor: Color {
        switch session.channel {
        case .master: .white
        case .red: .red
        case .green: .green
        case .blue: .blue
        }
    }

    var body: some View {
        EditorToolPresentation(title: "Tone Curve", header: { EmptyView() }) {
            EditorPanelScroll {
                VStack(spacing: 18) {
                    if !isDocked {
                    if let image = session.image {
                        Image(uiImage: image).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 160)
                            .accessibilityLabel("Photo with saved tone curves")
                    } else {
                        ProgressView("Preparing photo…").frame(height: 140)
                    }
                    }
                    HStack(spacing: 14) {
                        Image(lightCraftIcon: "LightCraft-Curve").foregroundStyle(LightCraftPanelStyle.label)
                        ForEach(ToneCurveChannel.allCases) { channel in
                            Button {
                                session.channel = channel; session.selectedPoint = nil
                            } label: {
                                Circle().stroke(channelColor(channel), lineWidth: 2)
                                    .frame(width: 20, height: 20)
                                    .padding(5)
                                    .background(session.channel == channel ? LightCraftPanelStyle.label.opacity(0.15) : .clear, in: .circle)
                            }
                            .accessibilityLabel("\(channel.title) curve")
                            .accessibilityAddTraits(session.channel == channel ? .isSelected : [])
                            .contextMenu { Button("Reset Channel") { Task { await session.reset(all: false) } } }
                        }
                        Spacer(minLength: 0)
                    }.buttonStyle(.plain).disabled(session.busy || dragging)

                    graph
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 260)
                        // Leave scrollable space beside the graph's point-drag gesture.
                        .padding(.horizontal, 16)
                        .disabled(session.busy || !session.loaded)
                    HStack {
                        Text("Point Curve").foregroundStyle(session.currentPreset == "Linear" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                        Menu(session.currentPreset) {
                            ForEach(session.presetNames, id: \.self) { name in
                                Button(name) { Task { await session.presetCommand("curve.applyPreset", params: ["name": name]) } }
                            }
                            Divider()
                            Button("Save Point Curve…") { presetName = ""; savingPreset = true }.disabled(session.currentPreset == "Linear")
                            Button("Import Presets…") { importingPresets = true }
                            Button("Export Presets…") {
                                Task {
                                    let file = URL.temporaryDirectory.appending(path: "Curves-\(UUID()).lccurve")
                                    await session.presetCommand("curve.exportPresets", params: ["path": file.path])
                                    if session.error == nil { exportedPresets = file; sharingPresets = true }
                                }
                            }.disabled(session.userPresetNames.isEmpty)
                        }.foregroundStyle(session.currentPreset == "Linear" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                        Spacer(minLength: 0)
                        Button("Reset") { Task { await session.resetAllCurves() } }.buttonStyle(.bordered)
                    }.font(.system(size: 14)).disabled(session.busy || dragging)
                    DisclosureGroup("Point Details") {
                        Text("Tap the graph to add a point. Drag a point to adjust it.").font(.caption)
                        if session.loaded { pointControls }
                    }
                    if session.busy { ProgressView("Updating photo…") }
                    if let error = session.error {
                        Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(20)
            }

            .interactiveDismissDisabled(session.busy || dragging)
            .task { await session.load(showsPreview: !isDocked) }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && dragging {
                    dragging = false
                    Task { await session.commit() }
                }
            }
        }
        .alert("Save Point Curve", isPresented: $savingPreset) {
            TextField("Preset name", text: $presetName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { Task { await session.presetCommand("curve.savePreset", params: ["name": presetName]) } }
                .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || presetName.count > 256)
        }
        .fileImporter(isPresented: $importingPresets, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): Task { await session.importPresets(url) }
            case .failure(let error): session.error = error.localizedDescription
            }
        }
        .sheet(isPresented: $sharingPresets, onDismiss: {
            if let exportedPresets { try? FileManager.default.removeItem(at: exportedPresets) }
            exportedPresets = nil
        }) { if let exportedPresets { PhotoShareSheet(files: [exportedPresets]) } }
        .preferredColorScheme(.dark)
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
    }

    private func channelColor(_ channel: ToneCurveChannel) -> Color {
        switch channel { case .master: LightCraftPanelStyle.text; case .red: .red; case .green: .green; case .blue: .blue }
    }
    private var graph: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvasSize in
                let inset: CGFloat = 14
                let width = max(1, canvasSize.width - inset * 2)
                let height = max(1, canvasSize.height - inset * 2)
                func point(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: inset + x * width, y: inset + (1 - y) * height)
                }
                var grid = Path()
                for i in 0...4 {
                    let f = Double(i) / 4
                    grid.move(to: point(f, 0)); grid.addLine(to: point(f, 1))
                    grid.move(to: point(0, f)); grid.addLine(to: point(1, f))
                }
                context.stroke(grid, with: .color(.white.opacity(0.15)), lineWidth: 1)
                var identity = Path()
                identity.move(to: point(0, 0)); identity.addLine(to: point(1, 1))
                context.stroke(identity, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                if let curve = session.curves[session.channel] {
                    var path = Path()
                    for sample in 0...256 {
                        let x = Double(sample) / 256
                        let p = point(x, curve.value(at: x))
                        if sample == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    context.stroke(path, with: .color(curveColor), lineWidth: 2)
                }
                for (index, p) in session.points.enumerated() {
                    let center = point(p.x, p.y)
                    let selected = index == session.selectedPoint
                    let radius: CGFloat = selected ? 7 : 5
                    let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                    context.fill(dot, with: .color(selected ? .accentColor : curveColor))
                    context.stroke(dot, with: .color(.black), lineWidth: 1)
                }
            }
            .background(LightCraftPanelStyle.inset, in: .rect(cornerRadius: 3))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($graphTouchActive) { _, active, _ in active = true }
                .onChanged { value in
                let width = max(1, size.width - 28), height = max(1, size.height - 28)
                let x = min(1, max(0, (value.location.x - 14) / width))
                let y = min(1, max(0, 1 - (value.location.y - 14) / height))
                if !dragging {
                    dragging = true
                    session.begin(x: x, y: y, width: width, height: height)
                } else if hypot(value.translation.width, value.translation.height) > 2 {
                    session.move(x: x, y: y)
                }
            }.onEnded { _ in
                dragging = false
                Task { await session.commit() }
            })
            .onChange(of: graphTouchActive) { _, active in
                // Cancellation may omit onEnded (for example, an interrupted Pencil gesture).
                if !active && dragging {
                    dragging = false
                    Task { await session.commit() }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(session.channel.title) curve graph")
            .accessibilityValue("\(session.points.count) points. Use the point selector and Input and Output sliders below to edit precisely.")
        }
    }

    private var pointControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Picker("Point", selection: $session.selectedPoint) {
                    Text("Choose a point").tag(Optional<Int>.none)
                    ForEach(session.points.indices, id: \.self) { index in
                        Text("Point \(index + 1)").tag(Optional(index))
                    }
                }
                Button("Add Point", lightCraftIcon: "LightCraft-Plus") { Task { await session.addPoint() } }
                    .labelStyle(.iconOnly).help("Add Point").disabled(session.points.count >= 64)
                Button("Delete Point", lightCraftIcon: "LightCraft-Minus") { Task { await session.deletePoint() } }
                    .labelStyle(.iconOnly).help("Delete Point")
                    .disabled(session.selectedPoint == nil || session.selectedPoint == 0 || session.selectedPoint == session.points.count - 1)
            }
            if let point = session.selected {
                HStack {
                    Text("Input")
                    LightCraftNumberButton(title: "Curve Input", value: point.x * 255, range: 0...255, step: 1) { number in
                        session.move(x: number / 255, y: session.selected?.y ?? point.y)
                        Task { await session.commit() }
                    }.disabled(point.x == 0 || point.x == 1)
                    Text("Output")
                    LightCraftNumberButton(title: "Curve Output", value: point.y * 255, range: 0...255, step: 1) { number in
                        session.move(x: session.selected?.x ?? point.x, y: number / 255)
                        Task { await session.commit() }
                    }
                }.font(.caption.monospacedDigit())
                    .foregroundStyle(LightCraftPanelStyle.isChanged(point.x, from: point.y) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSlider(value: Binding(get: { session.selected?.x ?? 0 }, set: { session.move(x: $0, y: session.selected?.y ?? 0) }),
                       in: 0...1, step: 1.0 / 255, defaultValue: point.y, onEditingChanged: { editing in
                    dragging = editing
                    if !editing { Task { await session.commit() } }
                })
                .accessibilityLabel("Curve input")
                .disabled(point.x == 0 || point.x == 1)
                LightCraftSlider(value: Binding(get: { session.selected?.y ?? 0 }, set: { session.move(x: session.selected?.x ?? 0, y: $0) }),
                       in: 0...1, step: 1.0 / 255, defaultValue: point.x, onEditingChanged: { editing in
                    dragging = editing
                    if !editing { Task { await session.commit() } }
                })
                .accessibilityLabel("Curve output")
            }
        }
        .disabled(session.busy)
    }
}
