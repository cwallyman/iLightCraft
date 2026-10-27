//
//  PhotoCropSheet.swift
//  iLightCraft
//

import SwiftUI

struct PhotoCropSheet<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {

    @State
    private var crop: CropEditorSession<Engine, Importer>

    @State
    private var isApplying = false
    @State private var geometryExpanded = false
    @State private var geometryBusy = false
    @State private var geometrySession: AdvancedColorSession<Engine, Importer>
    private let model: EditorViewModel<Engine, Importer>

    @Environment(\.dismiss)
    private var dismiss

    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    private func closeTool() {
        if let closeDock { closeDock() } else { dismiss() }
    }

    init(model: EditorViewModel<Engine, Importer>, sharedSession: CropEditorSession<Engine, Importer>? = nil, sharedGeometry: AdvancedColorSession<Engine, Importer>? = nil) {
        self.model = model
        _geometrySession = State(initialValue: sharedGeometry ?? AdvancedColorSession(model: model, pointColor: false, optics: true))
        _crop = State(initialValue: sharedSession ?? CropEditorSession(model: model))
    }

    @State private var customWidth = "1"
    @State private var customHeight = "1"

    private var validCustomAspect: Bool {
        guard let width = Double(customWidth), let height = Double(customHeight) else { return false }
        return width.isFinite && height.isFinite && width > 0 && height > 0
    }

    var body: some View {
        EditorToolPresentation(title: "Crop", header: { EmptyView() }) {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    if !isDocked {
                        preview
                            .padding(24)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black)
                    }

                    LightCraftMenuList {
                        LightCraftMenuSection {
                            HStack {
                                Button("Left", lightCraftIcon: "LightCraft-Rotate") { Task { await crop.rotate(clockwise: false) } }
                                Spacer()
                                Button("Right", lightCraftIcon: "LightCraft-RotateClockwise") { Task { await crop.rotate(clockwise: true) } }
                                Spacer()
                                Menu("Flip", lightCraftIcon: "LightCraft-Flip") {
                                    Button("Horizontal") { Task { await crop.flip(horizontal: true) } }
                                    Button("Vertical") { Task { await crop.flip(horizontal: false) } }
                                }
                            }
                            .buttonStyle(.borderless)
                            Picker("Aspect ratio", selection: $crop.aspect) {
                                Text("Free").tag("free")
                                if crop.aspect == "current" { Text("Current").tag("current") }
                                Text("Original").tag("original")
                                ForEach(["1x1", "4x5", "5x7", "2x3", "4x3", "16x9"], id: \.self) { name in
                                    Text(name.replacingOccurrences(of: "x", with: ":")).tag(name)
                                }
                            }
                            .foregroundStyle(crop.aspect == "free" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                            .onChange(of: crop.aspect) { _, _ in crop.chooseAspect() }
                            if crop.aspect != "free" && crop.aspect != "original" && crop.aspect != "current" {
                                Toggle("Portrait crop", isOn: $crop.portrait).foregroundStyle(crop.portrait ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                                    .onChange(of: crop.portrait) { _, _ in crop.chooseAspect() }
                            }
                            Toggle("Lock Aspect Ratio", isOn: Binding(get: { crop.ratio != nil }, set: crop.lockAspect)).foregroundStyle(crop.ratio != nil ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                            Button("Swap Aspect") { crop.swapAspect() }.disabled(crop.ratio == nil)
                            DisclosureGroup("Custom Aspect Ratio") {
                                HStack {
                                    Text("Width")
                                    LightCraftNumberButton(title: "Crop ratio width", value: Double(customWidth) ?? 1, range: 0.01...100000, step: 0.01, decimals: 2) { customWidth = String($0) }
                                    Text(":")
                                    Text("Height")
                                    LightCraftNumberButton(title: "Crop ratio height", value: Double(customHeight) ?? 1, range: 0.01...100000, step: 0.01, decimals: 2) { customHeight = String($0) }
                                }
                                Button("Use Custom Ratio") {
                                    if let width = Double(customWidth), let height = Double(customHeight) { crop.setCustomAspect(width, height) }
                                }.disabled(!validCustomAspect)
                            }
                            Button(crop.straightening ? "Cancel Straighten Tool" : "Straighten Tool") { crop.straightening.toggle(); crop.straightenStroke = [] }
                            VStack {
                                HStack {
                                    Text("Straighten")
                                    Spacer()
                                    LightCraftNumberButton(title: "Straighten", value: crop.draft.crop.geometry.angle, range: -45...45, step: 0.1, decimals: 1) { crop.draft.crop.geometry.angle = $0 }
                                    Text("°")
                                }.foregroundStyle(LightCraftPanelStyle.isChanged(crop.draft.crop.geometry.angle, from: 0) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                                LightCraftSlider(value: $crop.draft.crop.geometry.angle, in: -45...45, step: 0.1)
                                    .accessibilityLabel("Straighten angle")
                            }
                            Picker("Overlay", selection: $crop.overlay) {
                                ForEach(["thirds", "grid", "golden", "diagonal", "triangle", "spiral", "none"], id: \.self) { Text($0.capitalized).tag($0) }
                            }
                            if crop.overlay == "triangle" || crop.overlay == "spiral" {
                                Button("Flip Overlay") { crop.flipOverlay.toggle() }
                            }
                            Button("Reset Crop") {
                                crop.draft.crop.geometry = .init()
                                crop.draft.crop.aspect = nil
                                crop.aspect = "free"
                            }
                        } footer: {
                            Text("Drag the corners on the main photo to crop, or drag inside to move. Pinch to zoom; use two fingers to pan. Done saves the crop; Geometry changes apply immediately.")
                        }
                        .disabled(geometrySession.guiding || geometryBusy)
                        geometryMenu
                        if let error = crop.error { Text(error).foregroundStyle(.red) }
                    }
                    .disabled(crop.isLoading)
                    .frame(height: isDocked ? geometry.size.height : min(350, geometry.size.height * 0.48))
                }
            }

            .safeAreaInset(edge: .bottom, spacing: 0) { cropActions }
            .disabled(isApplying)
            .interactiveDismissDisabled(isApplying)
            .task { await crop.loadPreview() }
        }
        .modifier(EditorToolBusyReporter(busy: isApplying || crop.isLoading || geometryBusy))
        .onChange(of: geometrySession.busy) { _, busy in
            if !busy { Task { await crop.loadPreview() } }
        }
        .onChange(of: geometryExpanded) { _, expanded in
            if !expanded {
                geometrySession.guiding = false; geometrySession.guideLines = []; geometrySession.guideStroke = []
                Task { await crop.loadPreview() }
            }
        }
    }

    private var geometryMenu: some View {
        DisclosureGroup(isExpanded: Binding(get: { geometryExpanded }, set: { expanded in
            if !geometryBusy && !isApplying { geometryExpanded = expanded }
        })) {
            OpticsPanel(session: geometrySession, geometryOnly: true, beforeGeometryEdit: prepareGeometryEdit)
                .environment(\.editorToolEmbedded, true)
                .environment(\.editorToolDocked, true)
                .environment(\.editorToolBusy, $geometryBusy)
            Text("Geometry changes apply immediately.").font(.caption).foregroundStyle(.secondary)
        } label: {
            Label("Geometry", lightCraftIcon: "LightCraft-Sliders")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.label)
                .frame(minHeight: 40)
        }
        .padding(.horizontal, 8)
        .background(LightCraftPanelStyle.inset, in: .rect(cornerRadius: 6))
    }
    /// Geometry actions use the saved crop orientation; simply opening the section saves nothing.
    private func prepareGeometryEdit() async -> Bool {
        guard crop.draft != model.cropSettings else { return true }
        isApplying = true; defer { isApplying = false }
        return await crop.apply()
    }

    private var cropActions: some View {
        HStack {

            Button("Cancel") { closeTool() }.disabled(isApplying || geometryBusy)
            Spacer()
            Button("Done") {
                Task {
                    isApplying = true
                    if await crop.apply() { closeTool() }
                    isApplying = false
                }
            }
            .disabled(crop.image == nil || crop.isLoading || isApplying || geometryBusy || geometrySession.guiding)

        }
        .buttonStyle(.bordered).frame(maxWidth: .infinity).padding(10)
        .background(LightCraftPanelStyle.background)
    }

    private var preview: some View {
        GeometryReader { proxy in
            if let image = crop.image {
                let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                ZStack {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .rotationEffect(.degrees(crop.previewAngle))
                        .clipped()
                    CropSelection(rectangle: $crop.selection, imageSize: image.size, ratio: crop.ratio)
                        .frame(width: size.width, height: size.height)
                }
                .frame(width: size.width, height: size.height)
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                .disabled(crop.isLoading)
            }
            if crop.isLoading {
                ProgressView("Preparing photo…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
