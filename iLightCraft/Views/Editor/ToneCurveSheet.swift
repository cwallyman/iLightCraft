import SwiftUI

struct ToneCurveSheet<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: ToneCurveSession<Engine, Importer>
    @State private var dragging = false
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
        EditorToolPresentation(title: "Tone Curves", header: {
            Button("Undo", systemImage: "arrow.uturn.backward") { Task { await session.undo() } }
                .help("Undo").disabled(!session.model.canUndo || session.busy || dragging)
            Button("Redo", systemImage: "arrow.uturn.forward") { Task { await session.undo(redo: true) } }
                .help("Redo").disabled(!session.model.canRedo || session.busy || dragging)
            Button("Done") { closeTool() }.disabled(session.busy || dragging)
        }) {
            ScrollView {
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
                    Picker("Curve channel", selection: $session.channel) {
                        ForEach(ToneCurveChannel.allCases) { channel in Text(channel.title).tag(channel) }
                    }
                    .pickerStyle(.segmented)
                    .disabled(session.busy || dragging)
                    .onChange(of: session.channel) { _, _ in session.selectedPoint = nil }

                    graph
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 260)
                        // Leave scrollable space beside the graph's point-drag gesture.
                        .padding(.horizontal, 16)
                        .disabled(session.busy || !session.loaded)
                    Text("Tap to add a point. Drag to change it; release to update the photo.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if session.loaded {
                        pointControls
                    }
                    HStack {
                        Button("Reset Channel") { Task { await session.reset(all: false) } }
                        Spacer()
                        Button("Reset All Channels") { Task { await session.reset(all: true) } }
                    }
                    .disabled(session.busy || dragging)
                    if session.busy { ProgressView("Updating photo…") }
                    if let error = session.error {
                        Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding(20)
            }

            .interactiveDismissDisabled(session.busy || dragging)
            .task { await session.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active && dragging {
                    dragging = false
                    Task { await session.commit() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
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
            .background(.black.opacity(0.5), in: .rect(cornerRadius: 12))
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
                Button("Add Point", systemImage: "plus") { Task { await session.addPoint() } }
                    .labelStyle(.iconOnly).help("Add Point").disabled(session.points.count >= 64)
                Button("Delete Point", systemImage: "minus") { Task { await session.deletePoint() } }
                    .labelStyle(.iconOnly).help("Delete Point")
                    .disabled(session.selectedPoint == nil || session.selectedPoint == 0 || session.selectedPoint == session.points.count - 1)
            }
            if let point = session.selected {
                Text("Input \(Int((point.x * 255).rounded())) · Output \(Int((point.y * 255).rounded()))")
                    .font(.caption.monospacedDigit())
                Slider(value: Binding(get: { session.selected?.x ?? 0 }, set: { session.move(x: $0, y: session.selected?.y ?? 0) }),
                       in: 0...1, step: 1.0 / 255, onEditingChanged: { editing in
                    dragging = editing
                    if !editing { Task { await session.commit() } }
                })
                .accessibilityLabel("Curve input")
                .disabled(point.x == 0 || point.x == 1)
                Slider(value: Binding(get: { session.selected?.y ?? 0 }, set: { session.move(x: session.selected?.x ?? 0, y: $0) }),
                       in: 0...1, step: 1.0 / 255, onEditingChanged: { editing in
                    dragging = editing
                    if !editing { Task { await session.commit() } }
                })
                .accessibilityLabel("Curve output")
            }
        }
        .disabled(session.busy)
    }
}
