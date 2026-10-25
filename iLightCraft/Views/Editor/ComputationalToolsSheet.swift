//
//  ComputationalToolsSheet.swift
//  iLightCraft
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
    @State private var colorDragging = false

    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    private func closeTool() {
        if let closeDock { closeDock() } else { dismiss() }
    }

    init(model: EditorViewModel<Engine, Importer>, initialSection: Int = 0, sharedSession: ComputationalToolsSession<Engine, Importer>? = nil, onMerged: @escaping @MainActor (PhotoID, URL) async -> Void, onRendered: @escaping @MainActor (URL) async -> Void, onIndexed: @escaping @MainActor (PhotoID, URL) async -> Void) {
        _section = State(initialValue: initialSection)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-iLightCraftShowComputational"), let value = UserDefaults.standard.string(forKey: "iLightCraftComputationalTool"), let tool = Int(value), (0...5).contains(tool) {
            _section = State(initialValue: tool)
        }
        #endif
        _session = State(initialValue: sharedSession ?? ComputationalToolsSession(model: model, onIndexed: onIndexed))
        _enhancementSession = State(initialValue: EnhancementSession(model: model, onOpen: onRendered))
        _lensSession = State(initialValue: LensBlurSession(model: model, onOpen: onRendered))
        _mergeSession = State(initialValue: PhotoMergeSession(model: model, onOpen: onMerged))
    }
    var body: some View {
        EditorToolPresentation(title: ComputationalTool(rawValue: section)?.title ?? "On-device Tools", header: {
            Button("Done") { closeTool() }
                .disabled(colorDragging || session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !isDocked {
                    Picker("Tool", selection: $section) {
                        Text("Masks").tag(0)
                        Text("Remove").tag(1)
                        Text("Library Analysis").tag(2)
                        Text("Merge").tag(3)
                        Text("Lens Blur").tag(4)
                        Text("AI Enhancement").tag(5)
                    }
                    .pickerStyle(.menu)
                    .disabled(colorDragging || session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
                    }
                    if section < 3 && (!isDocked || section == 2) { preview }
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

            .scrollDisabled(colorDragging)
            .task { await session.load() }
            .onDisappear { colorDragging = false; session.close() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active {
                    colorDragging = false
                    session.cancel(); lensSession.cancel(); enhancementSession.cancel()
                }
            }
            .interactiveDismissDisabled(session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
        }
        .preferredColorScheme(.dark)
        .modifier(EditorToolBusyReporter(busy: colorDragging || session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy))
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
            Text("Select with on-device models. Selections are stored with the edit, so rendering and export do not rerun the model.")
                .font(.footnote).foregroundStyle(.secondary)
            if !session.masks.isEmpty {
                Picker("Saved mask", selection: $session.selectedMask) {
                    Text("Choose a mask").tag(Optional<UInt32>.none)
                    ForEach(session.masks) { mask in Text("\(mask.name) (\(mask.id))").tag(Optional(mask.id)) }
                }.disabled(session.busy || colorDragging)
                .onChange(of: session.selectedMask) { _, _ in session.savedMaskChanged() }
                Picker("Selection operation", selection: $session.maskOperation) {
                    Text("New mask").tag("new"); Text("Add").tag("add")
                    Text("Subtract").tag("subtract"); Text("Intersect").tag("intersect")
                }
            }
            DisclosureGroup("Manual selections") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Selection tool", selection: Binding(get: { session.manualKind }, set: { session.beginManual($0) })) {
                        Text("Automatic / Object").tag("none")
                        Text("Brush").tag("brush"); Text("Linear gradient").tag("linear")
                        Text("Radial gradient").tag("radial"); Text("Luminance range").tag("luminanceRange")
                        Text("Color range").tag("colorRange")
                    }
                    if session.manualKind != "none" {
                        Text(session.manualKind == "colorRange" ? "Tap the target color on the main photo." : "Draw on the main photo. Pinch to zoom; pan with two fingers.")
                            .font(.footnote)
                        if session.manualKind == "brush" {
                            Text("Brush size"); Slider(value: $session.brushSize, in: 0.001...0.25)
                            Text("Flow"); Slider(value: $session.manualFlow, in: 1...100)
                            Text("Density"); Slider(value: $session.manualDensity, in: 1...100)
                        }
                        if session.manualKind == "luminanceRange" {
                            Text("Luminance low"); Slider(value: $session.luminanceLow, in: 0...1)
                            Text("Luminance high"); Slider(value: $session.luminanceHigh, in: 0...1)
                        }
                        if session.manualKind == "colorRange" {
                            Text(session.colorPoint == nil ? "No color sampled" : "Color point selected")
                            Text("Color range refinement"); Slider(value: $session.colorRefine, in: 0...100)
                        }
                        Text("Feather"); Slider(value: $session.manualFeather, in: 0...100)
                        HStack {
                            Button("Clear Selection") { session.manualPoints = []; session.colorPoint = nil }
                            Button("Apply Selection", action: session.applyManualMask).buttonStyle(.borderedProminent)
                        }
                    }
                }
                .disabled(session.busy || colorDragging)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                Button("Subject") { session.select(people: false, background: false) }
                Button("Background") { session.select(people: false, background: true) }
                Button("People") { session.select(people: true, background: false) }
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleOnly)
            .font(.callout)
            .lineLimit(2)
            .disabled(session.busy || session.image == nil || (session.maskOperation != "new" && session.selectedMask == nil))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                Button("Sky", systemImage: "cloud.sun", action: session.selectSky).help("Select Sky")
                Button("Each Person", systemImage: "person.2") { session.selectIndividuals(skin: false) }.help("Create a separate mask for each detected person")
                Button("Each Person’s Skin", systemImage: "hand.raised") { session.selectIndividuals(skin: true) }.help("Create separate face and body skin coverage for each detected person")
            }
            .buttonStyle(.bordered)
            .labelStyle(.titleOnly)
            .font(.callout)
            .lineLimit(2)
            .disabled(session.busy || session.image == nil)
            Button(session.isPickingObject ? "Cancel Object Pick" : "Pick an Object") { session.isPickingObject.toggle() }
                .disabled(session.busy || session.image == nil || (session.maskOperation != "new" && session.selectedMask == nil))
            if session.isPickingObject { Text("Tap the object in the main photo.").font(.footnote) }
            if session.maskOverlay != nil || session.tintedPreview != nil { Toggle("Show selection overlay", isOn: $session.showMaskOverlay) }
            if session.selectedMask != nil {
                MaskColorControls(values: $session.maskColor, busy: session.busy,
                                  apply: session.applyMaskAdjustments,
                                  colorize: session.colorizeMask,
                                  reset: session.resetMaskColor,
                                  onEditingChanged: { colorDragging = $0 })
                Text("Edge refinement")
                Slider(value: $session.refinement, in: 0...100, step: 1).accessibilityLabel("Mask edge refinement")
                Button("Apply Edge Refinement", action: session.refineMask).disabled(session.busy)
                HStack {
                    Button("Invert", action: session.invertMask)
                    Button("Delete Mask", role: .destructive, action: session.deleteMask)
                }.disabled(session.busy)
            }
            Text("People and skin masks are numbered left to right. Skin combines face and body skin and excludes the other detected people. Review the overlay: small or overlapping people and fine sky edges may need refinement.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private var removal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("Repair mode", selection: $session.removalMode) {
                Text("Remove").tag("remove"); Text("Heal").tag("heal"); Text("Clone").tag("clone")
            }.pickerStyle(.segmented).disabled(session.busy)
            Text("Draw on the main photo, then apply. Pinch to zoom; pan with two fingers. Clone copies pixels; Heal blends the source into the target.")
                .font(.footnote).foregroundStyle(.secondary)
            Text("Brush size"); Slider(value: $session.brushSize, in: 0.001...0.25)
            Text("Feather"); Slider(value: $session.removalFeather, in: 0...100)
            Text("Opacity"); Slider(value: $session.removalOpacity, in: 0...100)
            Button(session.isPickingSource ? "Cancel Source Pick" : "Choose Source on Photo") { session.isPickingSource.toggle() }
            Text(session.sourcePoint == nil ? "Source: automatic" : "Source: chosen on photo").font(.caption)
            Button("Use Automatic Source") { session.sourcePoint = nil; session.isPickingSource = false }
            HStack {
                Button("Clear Stroke") { session.stroke = [] }
                Button("Apply Repair", action: session.removeStroke).buttonStyle(.borderedProminent)
            }.disabled(session.busy || session.stroke.isEmpty)
            if !session.savedSpots.isEmpty {
                Picker("Saved repair", selection: $session.selectedSpot) {
                    Text("New repair").tag(Optional<Int>.none)
                    ForEach(session.savedSpots.indices, id: \.self) { Text("Repair \($0 + 1)").tag(Optional($0)) }
                }.onChange(of: session.selectedSpot) { _, _ in session.restoreSpotControls() }
                if session.selectedSpot != nil {
                    Button("Update Saved Repair", action: session.updateSavedSpot)
                    Button("Find Another Source", action: session.changeSpotSource)
                    Button("Restore This Area", role: .destructive, action: session.deleteSavedSpot)
                }
            }
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

/// Stable destinations shared by the toolbar, iPhone menu and tool sheet.
enum ComputationalTool: Int, CaseIterable, Identifiable {
    case masks, remove, analysis, merge, lensBlur, enhancement
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .masks: "Masks"
        case .remove: "Remove"
        case .analysis: "Library Analysis"
        case .merge: "Merge"
        case .lensBlur: "Lens Blur"
        case .enhancement: "AI Enhancement"
        }
    }
    var symbol: String {
        switch self {
        case .masks: "person.crop.rectangle.badge.plus"
        case .remove: "eraser"
        case .analysis: "text.magnifyingglass"
        case .merge: "square.stack.3d.up"
        case .lensBlur: "camera.aperture"
        case .enhancement: "sparkles"
        }
    }
}
