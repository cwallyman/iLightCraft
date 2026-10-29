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
    @State private var showLensBlurInfo = false
    @State private var showsAddMask = false
    private let splitMaskLayout: Bool

    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    private var isPadStyle: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }

    private func closeTool() {
        if let closeDock { closeDock() } else { dismiss() }
    }

    init(model: EditorViewModel<Engine, Importer>, initialSection: Int = 0, sharedSession: ComputationalToolsSession<Engine, Importer>? = nil, splitMaskLayout: Bool = false, onMerged: @escaping @MainActor (PhotoID, URL) async -> Void, onRendered: @escaping @MainActor (URL) async -> Void, onLensBlurred: @escaping @MainActor (URL) async -> Void, onIndexed: @escaping @MainActor (PhotoID, URL) async -> Void) {
        self.splitMaskLayout = splitMaskLayout
        _section = State(initialValue: initialSection)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-iLightCraftShowComputational"), let value = UserDefaults.standard.string(forKey: "iLightCraftComputationalTool"), let tool = Int(value), (0...5).contains(tool) {
            _section = State(initialValue: tool)
        }
        #endif
        _session = State(initialValue: sharedSession ?? ComputationalToolsSession(model: model, onIndexed: onIndexed))
        _enhancementSession = State(initialValue: EnhancementSession(model: model, onOpen: onRendered))
        _lensSession = State(initialValue: LensBlurSession(model: model, onOpen: onLensBlurred))
        _mergeSession = State(initialValue: PhotoMergeSession(model: model, onOpen: onMerged))
    }
    var body: some View {
        EditorToolPresentation(title: section == 0 && splitMaskLayout ? (session.masks.first(where: { $0.id == session.selectedMask })?.name ?? "Masks") : (ComputationalTool(rawValue: section)?.title ?? "On-device Tools"),
                               titleAccessory: section == 4 ? AnyView(lensBlurInfo) : nil, header: {
            if section >= 2 {
                Button("Done") { closeTool() }.disabled(colorDragging || session.busy || mergeSession.working || lensSession.busy || enhancementSession.busy)
            }
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
                    // AnyView keeps the nested view type small; the full type overflowed the stack on iPad.
                    if section == 0 { AnyView(masks) }
                    if section == 1 { AnyView(removal) }
                    if section == 2 { AnyView(analysis) }
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
    private var lensBlurInfo: some View {
        Button { showLensBlurInfo = true } label: {
            Image(systemName: "info.circle").font(.system(size: 16))
        }
        .accessibilityLabel("About Lens Blur")
        .popover(isPresented: $showLensBlurInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Lens Blur").font(.headline)
                Text("Depth estimation runs on your device. Focus uses relative depth, not meters. The result is a separate TIFF copy; Undo returns to the original photo. The original is not overwritten.")
                Text("Bokeh shapes and painted depth refinement are not available yet.")
                if let url = URL(string: DepthModelStore.modelPage) { Link("Model and Apache-2.0 license", destination: url) }
            }
            .font(.subheadline).padding(20).frame(maxWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }

    @ViewBuilder private var preview: some View {
        if let image = session.displayedImage {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .overlay {
                    if section == 0, session.showMaskOverlay, session.tintedPreview == nil, let overlay = session.maskOverlay {
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
        VStack(alignment: .leading, spacing: 16) {
            if !splitMaskLayout && isPadStyle {
                HStack(spacing: 8) {
                    Button { showsAddMask = true } label: {
                        Label("Add Mask", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 46)
                            .lightCraftGlassButton(prominent: true)
                    }
                    .buttonStyle(.plain)
                    .disabled(session.busy || colorDragging || session.image == nil)
                    .popover(isPresented: $showsAddMask) {
                        MaskTypeGrid(session: session) { showsAddMask = false }
                            .padding(16).frame(width: 340)
                            .presentationCompactAdaptation(.popover)
                    }
                    Menu {
                        Button("Reset Mask Adjustments", action: session.resetMaskColor).disabled(session.selectedMask == nil)
                    } label: {
                        Image(systemName: "ellipsis").frame(width: 46, height: 46).glassEffect(.regular, in: .circle)
                    }
                    .accessibilityLabel("Masking Options").disabled(session.busy)
                }
            } else if !splitMaskLayout {
            HStack {
                Text("Create New Mask").foregroundStyle(.secondary)
                Spacer()
                Menu("Masking Options", lightCraftIcon: "LightCraft-More") {
                    Button("All People") { session.select(people: true, background: false) }
                    Button("Reset Mask Adjustments", action: session.resetMaskColor).disabled(session.selectedMask == nil)
                }.labelStyle(.iconOnly).disabled(session.busy)
            }
            maskTiles
            }
            if session.maskingContentAware {
                Text("Content-Aware").font(.system(size: 15, weight: .semibold))
                Text("Paint the area to fill on the photo, then apply. The area is rebuilt using surrounding texture.").font(.footnote)
                repairBrushControls
            } else if session.manualKind != "none" {
                manualMaskControls
            }
            if !splitMaskLayout {
            Divider()
            HStack {
                Text("Masks").font(.system(size: isPadStyle ? 16 : 15, weight: isPadStyle ? .bold : .semibold))
                    .foregroundStyle(isPadStyle ? Color.white : LightCraftPanelStyle.label)
                Spacer()
                Button(session.showMaskOverlay ? "Hide Overlay" : "Show Overlay", lightCraftIcon: session.showMaskOverlay ? "LightCraft-Eye" : "LightCraft-EyeOff") { session.showMaskOverlay.toggle() }
                    .labelStyle(.iconOnly).frame(width: 44, height: 44)
            }
            if session.masks.isEmpty { Text("No masks yet").foregroundStyle(.secondary) }
            ForEach(session.masks) { mask in
                let active = session.selectedMask == mask.id
                HStack {
                    Button {
                        session.beginManual("none"); session.selectedMask = mask.id; session.savedMaskChanged()
                    } label: {
                        if isPadStyle {
                            HStack(spacing: 10) {
                                Image(lightCraftIcon: "LightCraft-Mask").resizable().scaledToFit().frame(width: 18, height: 18)
                                    .frame(width: 40, height: 32)
                                    .background(Color.white.opacity(0.08), in: .rect(cornerRadius: 8))
                                Text(mask.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                        } else {
                            Label(mask.name, lightCraftIcon: "LightCraft-Mask").frame(maxWidth: .infinity, alignment: .leading).frame(minHeight: 44)
                        }
                    }.buttonStyle(.plain)
                    .accessibilityValue(active ? "Selected" : "")
                    .accessibilityAddTraits(active ? .isSelected : [])
                    Button("Toggle mask visibility", lightCraftIcon: mask.visible == false ? "LightCraft-EyeOff" : "LightCraft-Eye") { session.toggleVisibility(mask.id) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
                .padding(.horizontal, 8)
                .foregroundStyle(isPadStyle ? Color.white : (active ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label))
                .background {
                    if isPadStyle {
                        if active { RoundedRectangle(cornerRadius: 12).fill(LightCraftPanelStyle.highlight.opacity(0.28)) }
                        else { Color.clear.lightCraftCardSurface(cornerRadius: 12) }
                    } else {
                        RoundedRectangle(cornerRadius: 5).fill(active ? LightCraftPanelStyle.changed.opacity(0.14) : LightCraftPanelStyle.inset)
                    }
                }
                .overlay { if isPadStyle && active { RoundedRectangle(cornerRadius: 12).strokeBorder(LightCraftPanelStyle.highlight.opacity(0.3)) } }
                .disabled(session.busy || colorDragging)
            }
            }
            if session.selectedMask != nil {
                maskOverlayControls
                Divider()
                maskComponentControls
                Divider()
                MaskColorControls(values: $session.maskColor, busy: session.busy,
                                  apply: session.applyMaskAdjustments,
                                  colorize: session.colorizeMask,
                                  reset: session.resetMaskColor,
                                  onEditingChanged: { colorDragging = $0 }, grouped: isPadStyle)
                LightCraftSliderRow("Edge refinement", value: $session.refinement, in: 0...100, defaultValue: 0, step: 1) { editing in
                    colorDragging = editing
                    if !editing { session.refineMask() }
                }.accessibilityLabel("Mask edge refinement")
            } else if splitMaskLayout {
                Text("Select or create a mask to adjust it.").foregroundStyle(.secondary)
            }
        }
    }
    private var maskTiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            maskTile("Subject", icon: "LightCraft-Subject") { session.select(people: false, background: false) }
            maskTile("Sky", icon: "LightCraft-Sky", action: session.selectSky)
            maskTile("Background", icon: "LightCraft-Subject") { session.select(people: false, background: true) }
            maskTile("Brush", icon: "LightCraft-Brush") { session.beginManual("brush") }
            maskTile("Linear", icon: "LightCraft-Linear") { session.beginManual("linear") }
            maskTile("Radial", icon: "LightCraft-Radial") { session.beginManual("radial") }
            maskTile("Luminance", icon: "LightCraft-Sliders") { session.beginManual("luminanceRange") }
            maskTile("Color", icon: "LightCraft-Picker") { session.beginManual("colorRange") }
            maskTile("Each Person", icon: "LightCraft-Subject") { session.selectIndividuals(skin: false) }
            maskTile("Each Person’s Skin", icon: "LightCraft-Brush") { session.selectIndividuals(skin: true) }
            maskTile("Content-Aware", icon: "LightCraft-GridSquare", action: session.beginContentAware)
            maskTile("Object", icon: "LightCraft-FaceBox") {
                let picking = !session.isPickingObject
                session.beginManual("none"); session.isPickingObject = picking
            }
        }
        .disabled(session.busy || colorDragging || session.image == nil)
    }
    private func maskTile(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(lightCraftIcon: icon).resizable().scaledToFit().frame(width: 23, height: 23)
                Text(title).font(.system(size: 11)).lineLimit(3).minimumScaleFactor(0.8).multilineTextAlignment(.center)
            }
            .padding(.horizontal, 3).frame(maxWidth: .infinity, minHeight: 76)
            .background(LightCraftPanelStyle.inset, in: .rect(cornerRadius: 5))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(LightCraftPanelStyle.label).accessibilityLabel(title)
    }
    private var manualMaskControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.manualKind == "colorRange" ? "Tap the target color on the photo." : "Draw on the photo. Pinch to zoom; pan with two fingers.").font(.footnote)
            if session.manualKind == "brush" {
                LightCraftSliderRow("Size", value: $session.brushSize, in: 0.001...0.25, defaultValue: 0.025)
                LightCraftSliderRow("Flow", value: $session.manualFlow, in: 1...100, defaultValue: 100)
                LightCraftSliderRow("Density", value: $session.manualDensity, in: 1...100, defaultValue: 100)
            }
            if session.manualKind == "luminanceRange" {
                LightCraftSliderRow("Luminance Low", value: $session.luminanceLow, in: 0...1, defaultValue: 0)
                LightCraftSliderRow("Luminance High", value: $session.luminanceHigh, in: 0...1, defaultValue: 1)
            }
            if session.manualKind == "colorRange" {
                Text(session.colorPoint == nil ? "No color sampled" : "Color selected")
                LightCraftSliderRow("Refine", value: $session.colorRefine, in: 0...100, defaultValue: 50)
            }
            LightCraftSliderRow("Feather", value: $session.manualFeather, in: 0...100, defaultValue: 60)
            HStack {
                Button("Clear") { session.manualPoints = []; session.colorPoint = nil }
                Button("Apply Selection", action: session.applyManualMask)
            }.buttonStyle(.bordered)
        }.disabled(session.busy || colorDragging)
    }
    private var maskOverlayControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Overlay", selection: $session.overlayMode) {
                Text("Color Overlay").tag("color"); Text("Color Overlay on B&W").tag("colorOnBw")
                Text("Image on Black").tag("imageOnBlack"); Text("Image on White").tag("imageOnWhite")
                Text("White on Black").tag("whiteOnBlack")
            }.pickerStyle(.menu).foregroundStyle(session.overlayMode == "color" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed).onChange(of: session.overlayMode) { _, _ in session.refreshOverlay() }
            if session.overlayMode == "color" || session.overlayMode == "colorOnBw" {
                HStack(spacing: 10) {
                    ForEach(Array([[UInt8(255), 0, 0], [0, 200, 40], [0, 110, 255], [255, 215, 0], [255, 255, 255]].enumerated()), id: \.offset) { index, rgb in
                        Button {
                            session.overlayColor = rgb; session.refreshOverlay()
                        } label: {
                            RoundedRectangle(cornerRadius: 4).fill(Color(red: Double(rgb[0]) / 255, green: Double(rgb[1]) / 255, blue: Double(rgb[2]) / 255))
                                .frame(width: 22, height: 22).padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(session.overlayColor == rgb ? LightCraftPanelStyle.text : .clear, lineWidth: 1))
                        }.buttonStyle(.plain).accessibilityLabel(["Red", "Green", "Blue", "Yellow", "White"][index] + " overlay")
                    }
                }
                LightCraftSliderRow("Opacity", value: $session.overlayOpacity, in: 0...100, defaultValue: 35, step: 1) { editing in
                    colorDragging = editing
                    if !editing { session.refreshOverlay() }
                }.accessibilityLabel("Overlay opacity")
            }
            Toggle("Show Pins", isOn: $session.showPins)
        }.disabled(session.busy)
    }
    private var maskComponentControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selected = session.masks.first(where: { $0.id == session.selectedMask }) {
                ForEach(Array((selected.components ?? []).enumerated()), id: \.offset) { index, component in
                    HStack {
                        Label(component.name ?? (selected.components?.count == 1 ? selected.name : component.shape.kind.capitalized), lightCraftIcon: "LightCraft-Mask")
                        Spacer()
                        Menu("Component Options", lightCraftIcon: "LightCraft-More") {
                            Button("Invert") { session.componentAction(index, action: "invert") }
                            Button("Duplicate") { session.componentAction(index, action: "duplicate") }
                            Button("Delete", role: .destructive) { session.componentAction(index, action: "delete") }
                        }.labelStyle(.iconOnly)
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach([("Add", "add"), ("Subtract", "subtract"), ("Intersect", "intersect")], id: \.1) { title, op in
                    Button(title) { session.maskingContentAware = false; session.maskOperation = op }
                        .tint(session.maskOperation == op ? Color.accentColor : LightCraftPanelStyle.label)
                }
            }.buttonStyle(.bordered)
            HStack {
                Button("New Mask") { session.beginManual("none"); session.stroke = []; session.maskOperation = "new" }
                Button("Invert", action: session.invertMask)
                Button(role: .destructive, action: session.deleteMask) { Image(lightCraftIcon: "LightCraft-Trash") }.accessibilityLabel("Delete Mask")
            }.buttonStyle(.bordered)
            if session.maskOperation != "new" { Text("Choose a tool above to \(session.maskOperation) a selection.").font(.caption) }
        }.disabled(session.busy || colorDragging)
    }
    private var repairBrushControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            LightCraftSliderRow("Size", value: $session.brushSize, in: 0.001...0.25, defaultValue: 0.025)
            LightCraftSliderRow("Feather", value: $session.removalFeather, in: 0...100, defaultValue: 60)
            LightCraftSliderRow("Opacity", value: $session.removalOpacity, in: 0...100, defaultValue: 100)
            HStack {
                Button("Clear Stroke") { session.stroke = [] }
                Button("Apply Content-Aware", action: session.removeStroke).disabled(session.stroke.isEmpty)
            }.buttonStyle(.bordered)
        }.disabled(session.busy)
    }
    @ViewBuilder private var removal: some View {
        if isPadStyle { padRemoval } else { classicRemoval }
    }
    /// padRemoval is the iPad Remove panel in the card style used by Crop and Masks.
    private var padRemoval: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach([("remove", "Remove"), ("fill", "Content-Aware"), ("heal", "Heal"), ("clone", "Clone")], id: \.0) { mode, title in
                    removalCard(title, selected: session.removalMode == mode) {
                        session.removalMode = mode
                        if mode == "fill" { session.sourcePoint = nil; session.isPickingSource = false }
                    }
                }
            }.disabled(session.busy)
            VStack(spacing: 14) {
                LightCraftSliderRow("Brush size", value: $session.brushSize, in: 0.001...0.25, defaultValue: 0.025)
                LightCraftSliderRow("Feather", value: $session.removalFeather, in: 0...100, defaultValue: 60)
                LightCraftSliderRow("Opacity", value: $session.removalOpacity, in: 0...100, defaultValue: 100)
            }
            .padding(14).lightCraftCardSurface(cornerRadius: 14)
            if session.removalMode != "fill" {
                Text("Source").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                HStack(spacing: 8) {
                    removalCard("Automatic", selected: session.sourcePoint == nil && !session.isPickingSource) {
                        session.sourcePoint = nil; session.isPickingSource = false
                    }
                    removalCard(session.isPickingSource ? "Tap Photo…" : "Pick on Photo", selected: session.isPickingSource || session.sourcePoint != nil) {
                        session.isPickingSource.toggle()
                    }
                }.disabled(session.busy)
            }
            HStack(spacing: 8) {
                Button("Clear Stroke") { session.stroke = [] }.buttonStyle(.plain).lightCraftGlassButton()
                Spacer(minLength: 0)
                Button("Apply", action: session.removeStroke).buttonStyle(.plain).lightCraftGlassButton(prominent: true)
                    .accessibilityLabel("Apply repair")
            }.disabled(session.busy || session.stroke.isEmpty)
            HStack(spacing: 8) {
                Text("Spots").font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                Text("\(session.savedSpots.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
                Spacer(minLength: 0)
                Button("Find Dust", action: session.findDustSpots).buttonStyle(.plain).lightCraftGlassButton().disabled(session.busy)
            }
            if !session.savedSpots.isEmpty {
                HStack {
                    Text("Repair").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Menu {
                        Button { session.selectedSpot = nil; session.restoreSpotControls() } label: {
                            if session.selectedSpot == nil { Label("New repair", systemImage: "checkmark") } else { Text("New repair") }
                        }
                        ForEach(session.savedSpots.indices, id: \.self) { index in
                            Button { session.selectedSpot = index; session.restoreSpotControls() } label: {
                                if session.selectedSpot == index { Label("Repair \(index + 1)", systemImage: "checkmark") } else { Text("Repair \(index + 1)") }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(session.selectedSpot.map { "Repair \($0 + 1)" } ?? "New repair").lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                        }
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(minHeight: 32)
                        .lightCraftCardSurface(cornerRadius: 16).contentShape(.capsule)
                    }
                }
                if session.selectedSpot != nil {
                    HStack(spacing: 8) {
                        removalCard("Update", action: session.updateSavedSpot)
                        removalCard("New Source", action: session.changeSpotSource).disabled(session.removalMode == "fill")
                        removalCard("Delete", destructive: true, action: session.deleteSavedSpot)
                    }
                }
                removalCard("Delete All Spots", destructive: true, action: session.deleteAllSpots).disabled(session.busy)
            }
        }
    }
    private func removalCard(_ title: String, selected: Bool = false, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(destructive ? Color.red : (selected ? LightCraftPanelStyle.highlight : Color.white))
                .frame(maxWidth: .infinity, minHeight: 40).padding(.horizontal, 8)
                .lightCraftCardSurface(cornerRadius: 12)
                .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(LightCraftPanelStyle.highlight.opacity(0.5)) } }
                .contentShape(.rect)
        }.buttonStyle(.plain)
    }
    private var classicRemoval: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Remove").font(.system(size: 15, weight: .semibold))
            Picker("Repair mode", selection: $session.removalMode) {
                Text("Remove").tag("remove"); Text("Content-Aware").tag("fill"); Text("Heal").tag("heal"); Text("Clone").tag("clone")
            }.pickerStyle(.menu).disabled(session.busy)
            .foregroundStyle(session.removalMode == "remove" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
            .onChange(of: session.removalMode) { _, mode in
                if mode == "fill" { session.sourcePoint = nil; session.isPickingSource = false }
            }
            Text("\(session.savedSpots.count) spot(s) on this photo").font(.caption)
            Button("Find Dust Spots", action: session.findDustSpots).disabled(session.busy)
            Text("Draw on the main photo, then apply. Pinch to zoom; pan with two fingers. Clone copies pixels; Heal blends the source into the target.")
                .font(.footnote).foregroundStyle(.secondary)
            LightCraftSliderRow("Brush size", value: $session.brushSize, in: 0.001...0.25, defaultValue: 0.025)
            LightCraftSliderRow("Feather", value: $session.removalFeather, in: 0...100, defaultValue: 60)
            LightCraftSliderRow("Opacity", value: $session.removalOpacity, in: 0...100, defaultValue: 100)
            Button(session.isPickingSource ? "Cancel Source Pick" : "Choose Source on Photo") { session.isPickingSource.toggle() }.disabled(session.removalMode == "fill" || session.busy)
            Text(session.removalMode == "fill" ? "Source: surrounding texture" : (session.sourcePoint == nil ? "Source: automatic" : "Source: chosen on photo")).font(.caption)
            Button("Use Automatic Source") { session.sourcePoint = nil; session.isPickingSource = false }.disabled(session.removalMode == "fill")
            HStack {
                Button("Clear Stroke") { session.stroke = [] }
                Button("Apply Repair", action: session.removeStroke).buttonStyle(.borderedProminent)
            }.disabled(session.busy || session.stroke.isEmpty)
            if !session.savedSpots.isEmpty {
                Button("Delete All Spots", role: .destructive, action: session.deleteAllSpots).disabled(session.busy)
                Picker("Saved repair", selection: $session.selectedSpot) {
                    Text("New repair").tag(Optional<Int>.none)
                    ForEach(session.savedSpots.indices, id: \.self) { Text("Repair \($0 + 1)").tag(Optional($0)) }
                }.onChange(of: session.selectedSpot) { _, _ in session.restoreSpotControls() }
                if session.selectedSpot != nil {
                    Button("Update Saved Repair", action: session.updateSavedSpot)
                    Button("Find Another Source", action: session.changeSpotSource).disabled(session.removalMode == "fill")
                    Button("Delete", role: .destructive, action: session.deleteSavedSpot)
                }
            }
            Text("Content-Aware rebuilds the painted region from surrounding patches; Heal and Remove blend a source patch. These edits stay non-destructive.")
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
                .lightCraftTextField()
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
        case .masks: "Masking"
        case .remove: "Remove"
        case .analysis: "Library Analysis"
        case .merge: "Merge"
        case .lensBlur: "Lens Blur"
        case .enhancement: "AI Enhancement"
        }
    }
    var symbol: String {
        switch self {
        case .masks: "LightCraft-Mask"
        case .remove: "LightCraft-Eraser"
        case .analysis: "LightCraft-Search"
        case .merge: "LightCraft-Stack"
        case .lensBlur: "LightCraft-Radial"
        case .enhancement: "LightCraft-GradeHighlights"
        }
    }
}
