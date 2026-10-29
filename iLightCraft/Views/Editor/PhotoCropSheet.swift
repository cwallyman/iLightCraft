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
    private let pad = LightCraftPanelStyle.isPad

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
    @State private var showsCustomAspect = false

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
                            HStack(spacing: pad ? 8 : nil) {
                                cardButton { Task { await crop.rotate(clockwise: false) } } label: { Label("Left", lightCraftIcon: "LightCraft-Rotate") }
                                if !pad { Spacer() }
                                cardButton { Task { await crop.rotate(clockwise: true) } } label: { Label("Right", lightCraftIcon: "LightCraft-RotateClockwise") }
                                if !pad { Spacer() }
                                Menu {
                                    Button("Horizontal") { Task { await crop.flip(horizontal: true) } }
                                    Button("Vertical") { Task { await crop.flip(horizontal: false) } }
                                } label: { cardLabel { Label("Flip", lightCraftIcon: "LightCraft-Flip") } }
                            }
                            .buttonStyle(.borderless)
                            HStack {
                                Text("Aspect")
                                Spacer()
                                // Plain buttons, not a nested Picker, so one tap opens the choices.
                                Menu {
                                    menuChoice("Free", selected: crop.aspect == "free") { crop.aspect = "free" }
                                    if crop.aspect == "current" { menuChoice("Current", selected: true) {} }
                                    menuChoice("Original", selected: crop.aspect == "original") { crop.aspect = "original" }
                                    ForEach(["1x1", "4x5", "5x7", "2x3", "4x3", "16x9"], id: \.self) { name in
                                        menuChoice(name.replacingOccurrences(of: "x", with: ":"), selected: crop.aspect == name) { crop.aspect = name }
                                    }
                                    Divider()
                                    menuChoice("Custom…", selected: showsCustomAspect) { showsCustomAspect = true }
                                } label: { pillLabel(aspectTitle) }
                            }
                            .foregroundStyle(crop.aspect == "free" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                            .onChange(of: crop.aspect) { _, _ in crop.chooseAspect() }
                            Toggle("Lock Aspect Ratio", isOn: Binding(get: { crop.ratio != nil }, set: crop.lockAspect))
                                .tint(LightCraftPanelStyle.highlight)
                                .foregroundStyle(crop.ratio != nil ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                            HStack(spacing: 8) {
                                orientationButton("Portrait", icon: "rectangle.portrait", portrait: true)
                                orientationButton("Landscape", icon: "rectangle", portrait: false)
                            }
                            .disabled(crop.ratio == nil && crop.aspect == "free")
                            if showsCustomAspect {
                                HStack(spacing: 8) {
                                    Text("Custom")
                                    Spacer()
                                    LightCraftNumberButton(title: "Crop ratio width", value: Double(customWidth) ?? 1, range: 0.01...100000, step: 0.01, decimals: 2) { customWidth = String($0) }
                                    Text(":")
                                    LightCraftNumberButton(title: "Crop ratio height", value: Double(customHeight) ?? 1, range: 0.01...100000, step: 0.01, decimals: 2) { customHeight = String($0) }
                                }
                                HStack(spacing: 8) {
                                    cardButton { showsCustomAspect = false } label: { Text("Cancel") }
                                    cardButton(selected: true) {
                                        if let width = Double(customWidth), let height = Double(customHeight) { crop.setCustomAspect(width, height) }
                                        showsCustomAspect = false
                                    } label: { Text("Apply Ratio") }
                                    .disabled(!validCustomAspect)
                                }
                            }
                            VStack {
                                HStack {
                                    Text("Straighten")
                                    // Draw a line on the photo to level it.
                                    Button(crop.straightening ? "Cancel Straighten Tool" : "Straighten Tool", systemImage: "level") {
                                        crop.straightening.toggle(); crop.straightenStroke = []
                                    }
                                    .labelStyle(.iconOnly).buttonStyle(.plain)
                                    .foregroundStyle(crop.straightening ? LightCraftPanelStyle.highlight : LightCraftPanelStyle.label)
                                    .frame(width: 36, height: 36)
                                    .background { if crop.straightening { Circle().fill(LightCraftPanelStyle.highlight.opacity(0.2)) } }
                                    Spacer()
                                    LightCraftNumberButton(title: "Straighten", value: crop.draft.crop.geometry.angle, range: -45...45, step: 0.1, decimals: 1) { crop.draft.crop.geometry.angle = $0 }
                                    Text("°")
                                }.foregroundStyle(LightCraftPanelStyle.isChanged(crop.draft.crop.geometry.angle, from: 0) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                                LightCraftSlider(value: $crop.draft.crop.geometry.angle, in: -45...45, step: 0.1)
                                    .accessibilityLabel("Straighten angle")
                            }
                            HStack {
                                Text("Overlay")
                                Spacer()
                                Menu {
                                    ForEach(["thirds", "grid", "golden", "diagonal", "triangle", "spiral", "none"], id: \.self) { name in
                                        menuChoice(name.capitalized, selected: crop.overlay == name) { crop.overlay = name }
                                    }
                                } label: { pillLabel(crop.overlay.capitalized) }
                            }
                            HStack(spacing: 8) {
                                if crop.overlay == "triangle" || crop.overlay == "spiral" {
                                    cardButton { crop.flipOverlay.toggle() } label: { Text("Flip Overlay") }
                                }
                                cardButton {
                                    crop.draft.crop.geometry = .init()
                                    crop.draft.crop.aspect = nil
                                    crop.aspect = "original"
                                    crop.chooseAspect()
                                } label: { Label("Reset Crop", systemImage: "arrow.counterclockwise") }
                            }
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
        } label: {
            Label("Geometry", lightCraftIcon: "LightCraft-Sliders")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.label)
                .frame(minHeight: 40)
        }
        .padding(.horizontal, pad ? 12 : 8)
        .background { if pad { Color.clear.lightCraftCardSurface() } else { RoundedRectangle(cornerRadius: 6).fill(LightCraftPanelStyle.inset) } }
    }
    private var aspectTitle: String {
        switch crop.aspect {
        case "free": "Free"
        case "current": "Current"
        case "original": "Original"
        default: crop.aspect.replacingOccurrences(of: "x", with: ":")
        }
    }
    /// cardLabel draws a control as a raised card on iPad, matching Edit's tool rows.
    @ViewBuilder private func cardLabel<Content: View>(selected: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        if pad {
            content().font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(selected ? LightCraftPanelStyle.highlight : Color.white)
                .frame(maxWidth: .infinity, minHeight: 40).padding(.horizontal, 8)
                .lightCraftCardSurface(cornerRadius: 12)
                .overlay { if selected { RoundedRectangle(cornerRadius: 12).strokeBorder(LightCraftPanelStyle.highlight.opacity(0.5)) } }
                .contentShape(.rect)
        } else {
            content()
        }
    }
    private func cardButton<Content: View>(selected: Bool = false, action: @escaping () -> Void, @ViewBuilder label: () -> Content) -> some View {
        Button(action: action) { cardLabel(selected: selected, label) }.buttonStyle(.plain)
    }
    private func menuChoice(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { if selected { Label(title, systemImage: "checkmark") } else { Text(title) } }
    }
    /// pillLabel is the pop-up menu pill used by White Balance in Edit.
    @ViewBuilder private func pillLabel(_ title: String) -> some View {
        if pad {
            HStack(spacing: 6) {
                Text(title).lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12).frame(minHeight: 32)
            .lightCraftCardSurface(cornerRadius: 16)
            .contentShape(.capsule)
        } else {
            HStack(spacing: 4) { Text(title); Image(systemName: "chevron.up.chevron.down") }
        }
    }
    /// orientationButton sets the crop's orientation; fixed ratios re-apply, others swap when needed.
    private func orientationButton(_ title: String, icon: String, portrait: Bool) -> some View {
        let isPortrait = crop.ratio.map { $0 < 1 } ?? crop.portrait
        return cardButton(selected: isPortrait == portrait) {
            if ["free", "original", "current"].contains(crop.aspect) {
                if let ratio = crop.ratio, (ratio < 1) != portrait { crop.swapAspect() }
            } else {
                crop.portrait = portrait; crop.chooseAspect()
            }
        } label: { Label(title, systemImage: icon) }
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
        .buttonStyle(.bordered).frame(maxWidth: .infinity).padding(pad ? 14 : 10)
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
