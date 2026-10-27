import SwiftUI

/// The color mixer uses the same coalesced draft rendering and undo queue as basic Edit sliders.
struct HSLMixerPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var model: EditorViewModel<Engine, Importer>
    @State private var band: HSLColorBand = .red
    @State private var dragging = false
    @State private var working = false
    @State private var preview: UIImage?
    @State private var error: String?
    @State private var previewTask: Task<Void, Never>?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    private func close() {
        if let closeDock { closeDock() } else { dismiss() }
    }

    var body: some View {
        EditorToolPresentation(title: "HSL Mixer", header: { EmptyView() }) {
            EditorPanelScroll {
                VStack(alignment: .leading, spacing: 18) {
                    if !isDocked {
                        if let preview {
                            Image(uiImage: preview).resizable().aspectRatio(contentMode: .fit)
                                .frame(maxHeight: 180).accessibilityLabel("Photo with color adjustments")
                        } else { ProgressView("Preparing photo…") }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                        ForEach(HSLColorBand.allCases) { choice in
                            Button {
                                band = choice
                            } label: {
                                VStack(spacing: 6) {
                                    Circle().fill(color(choice)).frame(width: 18, height: 18)
                                    Text(choice.title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .padding(.vertical, 4)
                                .background(band == choice ? Color.accentColor.opacity(0.2) : .clear, in: .rect(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(band == choice ? Color.accentColor : .clear, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(choice.title)
                            .accessibilityAddTraits(band == choice ? .isSelected : [])
                        }
                    }
                    .disabled(working || dragging)
                    Text(band.title).font(.headline)
                    ForEach(band.controls, id: \.self) { kind in
                        AdjustmentSlider(
                            kind: kind,
                            value: model.values[kind] ?? 0,
                            defaultValue: model.defaultValue(of: kind),
                            onDragValue: { value in Task.immediate { await model.drag(kind, to: value) } },
                            onEditingChanged: { active in
                                dragging = active
                                if active { model.beginDrag(kind) }
                                else {
                                    working = true
                                    Task.immediate {
                                        await model.endDrag(kind)
                                        await refreshPreview()
                                        working = false
                                    }
                                }
                            },
                            onCommit: { commit(kind, value: $0) },
                            onNudge: { delta in
                                Task.immediate { await model.nudge(kind, by: delta) }
                                schedulePreview()
                            },
                            onReset: {
                                working = true
                                Task.immediate { await model.reset(kind); await refreshPreview(); working = false }
                            },
                            isCompact: false
                        )
                        .equatable()
                    }
                    .disabled(working || !model.isPhotoOpen || model.isShowingBefore)
                    VStack(alignment: .leading, spacing: 12) {
                        Button("Reset \(band.title)") { reset(all: false) }
                        Button("Reset All HSL Colors") { reset(all: true) }
                    }
                    .disabled(working || dragging || !model.isPhotoOpen || model.isShowingBefore)
                    Text("Hue changes the color; Saturation changes its intensity; Luminance changes its brightness.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if working { ProgressView("Updating photo…") }
                    if let message = error ?? model.errorMessage {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .scrollDisabled(dragging)
            .task { await refreshPreview() }
            .onDisappear { previewTask?.cancel() }
            .interactiveDismissDisabled(working || dragging)
        }
        .preferredColorScheme(.dark)
        .modifier(EditorToolBusyReporter(busy: working || dragging))
    }

    private func commit(_ kind: DevelopAdjustmentKind, value: Double) {
        working = true
        Task.immediate {
            model.beginDrag(kind)
            await model.drag(kind, to: value)
            await model.endDrag(kind)
            await refreshPreview()
            working = false
        }
    }
    private func reset(all: Bool) {
        working = true; error = nil
        let controls = band.controls
        Task.immediate {
            defer { working = false }
            do {
                if all {
                    _ = try await model.performPhotoEdit("develop.resetSection", params: ["section": "mixer"])
                } else {
                    let values = Dictionary(uniqueKeysWithValues: controls.map { ($0.rawValue, 0.0) })
                    _ = try await model.performPhotoEdit("develop.set", params: ResetRequest(values: values))
                }
                await refreshPreview()
            } catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
        }
    }
    private func undo(redo: Bool) {
        working = true
        Task.immediate {
            if redo { await model.redo() } else { await model.undo() }
            await refreshPreview(); working = false
        }
    }
    private func schedulePreview() {
        guard !isDocked else { return }
        previewTask?.cancel()
        previewTask = Task {
            do { try await Task.sleep(for: .milliseconds(400)); try Task.checkCancellation() }
            catch { return }
            await refreshPreview()
        }
    }
    private func refreshPreview() async {
        guard !isDocked else { return }
        let url = URL.temporaryDirectory.appending(path: "hsl-preview-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await model.photoCommand("ilightcraft.export", params: ToneCurveSession<Engine, Importer>.PreviewRequest(path: url.path))
            let bytes = try await Task.detached { try Data(contentsOf: url) }.value
            guard let image = UIImage(data: bytes) else { throw EngineError.engine("Cannot read the color preview") }
            preview = image; error = nil
        } catch { self.error = (error as? EngineError)?.message ?? error.localizedDescription }
    }
    nonisolated private struct ResetRequest: Encodable, Sendable { let values: [String: Double] }

    private func color(_ band: HSLColorBand) -> Color {
        switch band {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .aqua: .cyan
        case .blue: .blue
        case .purple: .purple
        case .magenta: Color(red: 1, green: 0, blue: 1)
        }
    }
}
