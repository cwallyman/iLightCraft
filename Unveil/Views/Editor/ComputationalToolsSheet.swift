//
//  ComputationalToolsSheet.swift
//  Unveil
//

import SwiftUI

/// ComputationalToolsSheet exposes implemented local analysis and editing without claiming missing models.
struct ComputationalToolsSheet<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: ComputationalToolsSession<Engine, Importer>
    @State private var enhancementSession: EnhancementSession<Engine, Importer>
    @State private var lensSession: LensBlurSession<Engine, Importer>
    @State private var mergeSession: PhotoMergeSession<Engine, Importer>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @State private var section = 0

    init(model: EditorViewModel<Engine, Importer>, onMerged: @escaping @MainActor (PhotoID, URL) async -> Void, onRendered: @escaping @MainActor (URL) async -> Void, onIndexed: @escaping @MainActor (PhotoID, URL) async -> Void) {
        #if DEBUG
        if let value = UserDefaults.standard.string(forKey: "UnveilComputationalTool"), let tool = Int(value), (0...5).contains(tool) {
            _section = State(initialValue: tool)
        }
        #endif
        _session = State(initialValue: ComputationalToolsSession(model: model, onIndexed: onIndexed))
        _enhancementSession = State(initialValue: EnhancementSession(model: model, onOpen: onRendered))
        _lensSession = State(initialValue: LensBlurSession(model: model, onOpen: onRendered))
        _mergeSession = State(initialValue: PhotoMergeSession(model: model, onOpen: onMerged))
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Tool", selection: $section) {
                        Text("Masks").tag(0)
                        Text("Remove").tag(1)
                        Text("Library Analysis").tag(2)
                        Text("Merge").tag(3)
                        Text("Lens Blur").tag(4)
                        Text("AI Enhancement").tag(5)
                    }
                    .pickerStyle(.menu)
                    .disabled(session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
                    if section < 3 { preview }
                    if section == 0 { masks }
                    if section == 1 { removal }
                    if section == 2 { analysis }
                    if section == 3 { PhotoMergePanel(session: mergeSession) }
                    if section == 4 { LensBlurPanel(session: lensSession) }
                    if section == 5 { EnhancementPanel(session: enhancementSession) }
                    if session.busy {
                        ProgressView(session.status)
                        Button("Cancel After Analysis", action: session.cancel)
                    } else if !session.status.isEmpty {
                        Text(session.status).font(.footnote).foregroundStyle(.secondary)
                    }
                    if let error = session.error {
                        Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle("On-device Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.disabled(session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
                }
            }
            .task { await session.load() }
            .onDisappear { session.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    session.cancel(); lensSession.cancel(); enhancementSession.cancel()
                }
            }
            .interactiveDismissDisabled(session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
        }
        .preferredColorScheme(.dark)
    }
    @ViewBuilder private var preview: some View {
        if let image = session.image {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    if section == 0, session.showMaskOverlay, let overlay = session.maskOverlay {
                        Image(uiImage: overlay).resizable().opacity(0.35).allowsHitTesting(false)
                    }
                    if section == 0 && session.isPickingObject {
                        GeometryReader { geometry in
                            Color.clear.contentShape(Rectangle()).gesture(SpatialTapGesture().onEnded { value in
                                guard !session.busy, geometry.size.width > 0, geometry.size.height > 0 else { return }
                                let point = CGPoint(x: value.location.x / geometry.size.width, y: value.location.y / geometry.size.height)
                                session.select(people: false, background: false, point: point)
                            })
                        }
                    }
                    if section == 1 {
                        GeometryReader { geometry in
                            Path { path in
                                guard let first = session.stroke.first else { return }
                                path.move(to: CGPoint(x: first.x * geometry.size.width, y: first.y * geometry.size.height))
                                for point in session.stroke.dropFirst() {
                                    path.addLine(to: CGPoint(x: point.x * geometry.size.width, y: point.y * geometry.size.height))
                                }
                            }
                            .stroke(.yellow.opacity(0.6), style: StrokeStyle(lineWidth: max(3, session.brushSize * max(geometry.size.width, geometry.size.height) * 2), lineCap: .round))
                            .contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                                guard !session.busy, geometry.size.width > 0, geometry.size.height > 0 else { return }
                                let point = CGPoint(x: min(1, max(0, value.location.x / geometry.size.width)),
                                                    y: min(1, max(0, value.location.y / geometry.size.height)))
                                if session.stroke.count < 2048 { session.stroke.append(point) }
                            })
                        }
                    }
                }
                .frame(maxHeight: 350)
                .accessibilityLabel(section == 1 ? "Draw a stroke over the area to remove" : "Uncropped analysis preview")
        } else {
            ProgressView("Preparing preview…").frame(maxWidth: .infinity, minHeight: 180)
        }
    }
    private var masks: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Select with Apple's on-device models. Selections are stored with the edit, so rendering and export do not rerun the model.")
                .font(.footnote).foregroundStyle(.secondary)
            if !session.masks.isEmpty {
                Picker("Saved mask", selection: $session.selectedMask) {
                    Text("Choose a mask").tag(Optional<UInt32>.none)
                    ForEach(session.masks) { mask in Text("\(mask.name) (\(mask.id))").tag(Optional(mask.id)) }
                }.onChange(of: session.selectedMask) { _, _ in session.restoreMaskControls() }
                Picker("Selection operation", selection: $session.maskOperation) {
                    Text("New mask").tag("new"); Text("Add").tag("add")
                    Text("Subtract").tag("subtract"); Text("Intersect").tag("intersect")
                }
            }
            HStack {
                Button("Subject") { session.select(people: false, background: false) }
                Button("Background") { session.select(people: false, background: true) }
                Button("People") { session.select(people: true, background: false) }
            }
            .buttonStyle(.bordered)
            .disabled(session.busy || session.image == nil || (session.maskOperation != "new" && session.selectedMask == nil))
            Button(session.isPickingObject ? "Cancel Object Pick" : "Pick an Object") { session.isPickingObject.toggle() }
                .disabled(session.busy || session.image == nil || (session.maskOperation != "new" && session.selectedMask == nil))
            if session.isPickingObject { Text("Tap the object in the preview.").font(.footnote) }
            if session.maskOverlay != nil { Toggle("Show selection overlay", isOn: $session.showMaskOverlay) }
            if session.selectedMask != nil {
                Text("Mask exposure: \(session.exposure, specifier: "%.2f") EV")
                Slider(value: $session.exposure, in: -4...4, step: 0.1)
                    .accessibilityLabel("Mask exposure")
                Button("Apply Mask Exposure", action: session.applyExposure)
                    .buttonStyle(.borderedProminent)
                    .disabled(session.busy)
                Text("Edge refinement")
                Slider(value: $session.refinement, in: 0...100, step: 1).accessibilityLabel("Mask edge refinement")
                Button("Apply Edge Refinement", action: session.refineMask).disabled(session.busy)
                HStack {
                    Button("Invert", action: session.invertMask)
                    Button("Delete Mask", role: .destructive, action: session.deleteMask)
                }.disabled(session.busy)
            }
            Text("Sky, landscape classes and individual body-part models are not included in this first local implementation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var removal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Draw on the uncropped preview, then apply. The engine chooses a nearby source patch and heals the area at render/export resolution.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Brush size")
            Slider(value: $session.brushSize, in: 0.005...0.08).accessibilityLabel("Removal brush size")
            HStack {
                Button("Clear Stroke") { session.stroke = [] }
                Button("Remove Area", action: session.removeStroke).buttonStyle(.borderedProminent)
            }
            .disabled(session.busy || session.stroke.isEmpty)
            Text("This is content-aware patch healing. Generative filling, reflection detection and background-people removal need additional models.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var analysis: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Classify this photo, read visible text and count detected faces locally. Nothing is uploaded.")
                .font(.footnote).foregroundStyle(.secondary)
            Button("Analyze Photo", action: session.analyze)
                .buttonStyle(.borderedProminent).disabled(session.busy || session.image == nil)
            if let result = session.description {
                Text("Faces detected: \(result.faces)")
                Text(result.labels.joined(separator: ", ")).textSelection(.enabled)
                if !result.text.isEmpty {
                    Text("Visible text").font(.headline)
                    Text(result.text.joined(separator: "\n")).textSelection(.enabled)
                }
            }
            Divider()
            Button("Index Imported Library", action: session.indexImportedPhotos)
                .disabled(session.busy)
            Text("Indexes up to 1,000 already imported photos. It does not scan your whole Photos library. The private index is saved after each photo and can be rerun after edits.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Clear Private Analysis Index", role: .destructive, action: session.clearIndex)
                .disabled(session.busy)
            TextField("Search labels, visible text or people", text: $session.query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search private analysis index")
            ForEach(session.results.prefix(50)) { result in
                Button { session.openIndexed(result) } label: {
                    VStack(alignment: .leading) {
                        Text(result.name).lineLimit(1)
                        Text(result.analysis.labels.prefix(4).joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }.disabled(session.busy)
            }
            Text("Face counting is not identity recognition. Search matches indexed labels/OCR and uses local English text embeddings when available. It is not a joint image-text model; identity recognition remains separate work.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
