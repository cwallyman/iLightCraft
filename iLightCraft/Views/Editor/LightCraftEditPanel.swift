//
//  LightCraftEditPanel.swift
//  iLightCraft
//

import SwiftUI
import UIKit
import Observation

/// LightCraftEditSession reads every shared slider from the retained engine's control specs.
@Observable @MainActor
final class LightCraftEditSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    private(set) var controls: [NativeDevelopControl] = []
    var values: [String: Double] = [:]
    private(set) var busy = false
    var error: String?
    private(set) var profileName = "Color"
    private(set) var whiteBalanceMode = "asShot"
    private(set) var vignetteStyle = "highlightPriority"
    private(set) var lensCorrections = false
    private(set) var embeddedLens = false
    private(set) var isBlackAndWhite = false
    private(set) var removeCA = false
    private(set) var disabledSections: Set<String> = []
    init(model: EditorViewModel<Engine, Importer>) { self.model = model }
    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await read() } catch { self.error = error.localizedDescription }
    }
    private func read() async throws {
        let text = try await model.photoCommand("develop.controls", params: [String: String]())
        let controls = try JSONDecoder().decode([NativeDevelopControl].self, from: Data(text.utf8))
        guard controls.count <= 4096, controls.allSatisfy(\.isValid) else { throw EngineError.engine("Invalid develop controls") }
        self.controls = controls
        values = Dictionary(controls.map { ($0.id, $0.value) }, uniquingKeysWith: { _, latest in latest })
        let settingsText = try await model.photoCommand("develop.get", params: [String: String]())
        if let settings = try JSONSerialization.jsonObject(with: Data(settingsText.utf8)) as? [String: Any] {
            whiteBalanceMode = (settings["wb"] as? [String: Any])?["mode"] as? String ?? "asShot"
            vignetteStyle = (settings["vignette"] as? [String: Any])?["style"] as? String ?? "highlightPriority"
            lensCorrections = (settings["optics"] as? [String: Any])?["lens_profile"] as? Bool ?? false
            removeCA = (settings["optics"] as? [String: Any])?["remove_ca"] as? Bool ?? false
            disabledSections = Set(settings["disabled_sections"] as? [String] ?? [])
            let profileID = (settings["profile"] as? [String: Any])?["id"] as? String ?? "lc.color"
            isBlackAndWhite = settings["treatment"] as? String == "bw" || profileID == "lc.mono" || profileID.hasPrefix("lc.bw.")
            let inspected = try await model.photoCommand("photo.inspect", params: [String: String]())
            let photo = try JSONSerialization.jsonObject(with: Data(inspected.utf8)) as? [String: Any]
            let lens = photo?["embedded_lens"] as? [String: Any]
            embeddedLens = [lens?["warp"], lens?["vignette"]].contains { value in value != nil && !(value is NSNull) }
            if let id = (settings["profile"] as? [String: Any])?["id"] as? String {
                let profilesText = try await model.photoCommand("profiles.list", params: [String: String]())
                let profiles = try JSONDecoder().decode([ProfileName].self, from: Data(profilesText.utf8))
                profileName = profiles.first { $0.id == id }?.name ?? "Color"
            }
        }
    }
    nonisolated private struct ProfileName: Decodable { let id: String; let name: String }
    func matching(_ prefixes: [String]) -> [NativeDevelopControl] {
        controls.filter { control in prefixes.contains { control.id.hasPrefix($0 + ".") } }
    }
    func apply(_ control: NativeDevelopControl) async {
        guard let value = values[control.id], value.isFinite, (control.min...control.max).contains(value) else { return }
        await command("develop.set", params: SetControl(control: control.id, value: value))
    }
    nonisolated struct SetControl: Encodable, Sendable { let control: String; let value: Double }
    func command(_ command: String, params: some Encodable & Sendable) async {
        guard !busy else { return }
        busy = true; error = nil; defer { busy = false }
        do { _ = try await model.performPhotoEdit(command, params: params); try await read() }
        catch { self.error = error.localizedDescription }
    }
}

/// LightCraftEditPanel follows the desktop's section and subsection order.
struct LightCraftEditPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    let model: EditorViewModel<Engine, Importer>
    @Binding var clipping: ClippingOverlay
    let openTool: (EditorDockTool) -> Void
    @State private var session: LightCraftEditSession<Engine, Importer>
    @State private var dragging = false
    @State private var childBusy: [String: Bool] = [:]
    @State private var pointColor: AdvancedColorSession<Engine, Importer>
    @State private var grading: AdvancedColorSession<Engine, Importer>
    @State private var whiteBalance: EditorAuxiliarySession<Engine, Importer>
    @State private var whiteBalancePicking = false
    let onWhiteBalancePicker: (EditorAuxiliarySession<Engine, Importer>?) -> Void
    let onColorPicker: (AdvancedColorSession<Engine, Importer>?) -> Void
    @State private var openSections: Set<String>
    @State private var soloMode = false
    private var isPadStyle: Bool {
        #if targetEnvironment(macCatalyst)
        false
        #else
        UIDevice.current.userInterfaceIdiom == .pad
        #endif
    }
    init(model: EditorViewModel<Engine, Importer>, group: AdjustmentGroup = .light, clipping: Binding<ClippingOverlay>, openTool: @escaping (EditorDockTool) -> Void, onColorPicker: @escaping (AdvancedColorSession<Engine, Importer>?) -> Void = { _ in }, onWhiteBalancePicker: @escaping (EditorAuxiliarySession<Engine, Importer>?) -> Void = { _ in }) {
        self.model = model; _clipping = clipping; self.openTool = openTool
        self.onColorPicker = onColorPicker
        self.onWhiteBalancePicker = onWhiteBalancePicker
        _whiteBalance = State(initialValue: EditorAuxiliarySession(model: model, mode: .whiteBalance))
        _pointColor = State(initialValue: AdvancedColorSession(model: model, pointColor: true))
        _grading = State(initialValue: AdvancedColorSession(model: model, pointColor: false))
        _session = State(initialValue: LightCraftEditSession(model: model))
        _openSections = State(initialValue: [group == .presence ? "Effects" : group.title])
    }
    var body: some View {
        VStack(spacing: 0) {
            if isPadStyle {
                HStack(spacing: 8) {
                    Text("Edit").font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 4)
                    Button { Task { await session.command("develop.auto", params: [String: String]()) } } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkle").foregroundStyle(LightCraftPanelStyle.highlight)
                            Text("Auto")
                        }.lightCraftGlassButton().fixedSize()
                    }
                    Button { Task { await model.resetAll(); await session.load() } } label: { Text("Reset").lightCraftGlassButton().fixedSize() }
                }.padding(.horizontal, 16).padding(.top, 14)
            }
            HistogramView(viewModel: model, clipping: $clipping, fixedPlotHeight: 68, showsCaptureSummary: true)
                .padding(isPadStyle ? 12 : 0)
                .modifier(PadCardSurface(enabled: isPadStyle))
                .padding(.horizontal, isPadStyle ? 14 : 12).padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: isPadStyle ? 12 : 14) {
                    HStack {
                        if !isPadStyle {
                            Text("Edit").font(.system(size: 17, weight: .semibold)).foregroundStyle(LightCraftPanelStyle.text)
                            Spacer()
                            Button("Auto") { Task { await session.command("develop.auto", params: [String: String]()) } }
                        }
                        Button { Task { await session.command("develop.treatment", params: [String: String]()) } } label: {
                            treatmentChip("B&W", on: session.isBlackAndWhite)
                        }
                        Button { Task { await model.setHDR(!model.hdrEnabled); await session.load() } } label: {
                            treatmentChip("HDR", on: model.hdrEnabled)
                        }
                        if !isPadStyle { Button("Reset") { Task { await model.resetAll(); await session.load() } } }
                    }
                    inlineTool("Profile: \(session.profileName)", icon: "LightCraft-ProfileGrid", changed: session.profileName != "Color" || LightCraftPanelStyle.isChanged(session.values["profile.amount"] ?? 100, from: 100)) {
                        ProfilesPanel(model: model)
                    }
                    if !isPadStyle { Divider() }
                    section("Light", id: "light") {
                        rows(["light"])
                        inlineTool("Curve", icon: "LightCraft-Curve") {
                            ToneCurveSheet(model: model)
                            namedRows(["curve.highlights", "curve.lights", "curve.darks", "curve.shadows", "curve.refineSaturation"])
                        }
                    }
                    section("Color", id: "color") {
                        HStack(spacing: isPadStyle ? 10 : 8) {
                            Text("White Balance").foregroundStyle(session.whiteBalanceMode == "asShot" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                            Spacer()
                            Menu {
                                ForEach([("As Shot", "asShot"), ("Auto", "auto"), ("Daylight", "daylight"), ("Cloudy", "cloudy"), ("Shade", "shade"), ("Tungsten", "tungsten"), ("Fluorescent", "fluorescent"), ("Flash", "flash")], id: \.1) { title, mode in
                                    Button { Task { await session.command("develop.wb", params: ["mode": mode]) } } label: {
                                        if session.whiteBalanceMode == mode { Label(title, systemImage: "checkmark") } else { Text(title) }
                                    }
                                }
                            } label: {
                                if isPadStyle {
                                    // A pill with an up-down chevron reads as a pop-up menu, like system pickers.
                                    HStack(spacing: 6) {
                                        Text(whiteBalanceTitle).lineLimit(1)
                                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                                    }
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 12).frame(minHeight: 32)
                                    .lightCraftCardSurface(cornerRadius: 16)
                                    .contentShape(.capsule)
                                } else {
                                    Text(whiteBalanceTitle)
                                }
                            }
                            .foregroundStyle(session.whiteBalanceMode == "asShot" ? (isPadStyle ? LightCraftPanelStyle.text : LightCraftPanelStyle.label) : LightCraftPanelStyle.changed)
                            .accessibilityLabel("White Balance Preset")
                            Button("White Balance Selector", lightCraftIcon: "LightCraft-Picker") {
                                pointColor.picking = false
                                whiteBalancePicking.toggle()
                                Task {
                                    if whiteBalancePicking { await whiteBalance.load() }
                                    onWhiteBalancePicker(whiteBalancePicking ? whiteBalance : nil)
                                }
                            }
                                .labelStyle(.iconOnly).help("White Balance Selector")
                                .foregroundStyle(whiteBalancePicking ? LightCraftPanelStyle.highlight : LightCraftPanelStyle.text)
                                .frame(width: 36, height: 36)
                                .background(whiteBalancePicking ? LightCraftPanelStyle.highlight.opacity(0.22) : .clear, in: .circle)
                                .accessibilityAddTraits(whiteBalancePicking ? .isSelected : [])
                        }
                        if whiteBalancePicking && !isPadStyle {
                            Text("Tap a neutral area on the photo. Tap the selector again to finish.").font(.caption)
                        }
                        whiteBalanceSliders
                        rows(["color"])
                        if session.isBlackAndWhite {
                            inlineTool("B&W Mixer", icon: "LightCraft-Radial") { rows(["bw"]) }
                        } else {
                            inlineTool("Color Mixer", icon: "LightCraft-Sliders") { HSLMixerPanel(model: model) }
                            inlineTool("Point Color", icon: "LightCraft-Picker") { AdvancedColorPanel(session: pointColor) }
                        }
                        inlineTool("Color Grading", icon: "LightCraft-GradeAll") { AdvancedColorPanel(session: grading) }
                    }
                    section("Effects", id: "effects") {
                        rows(["effects"])
                        subheading("Vignette")
                        Picker("Style", selection: Binding(get: { session.vignetteStyle }, set: { value in
                            Task { await session.command("develop.merge", params: ["settings": ["vignette": ["style": value]]]) }
                        })) {
                            Text("Highlight").tag("highlightPriority"); Text("Color").tag("colorPriority"); Text("Paint").tag("paintOverlay")
                        }.pickerStyle(.segmented).foregroundStyle(session.vignetteStyle == "highlightPriority" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                        rows(["vignette"])
                        subheading("Grain")
                        rows(["grain"])
                    }
                    section("Detail", id: "detail") {
                        subheading("Sharpening")
                        namedRows(["detail.sharpenAmount", "detail.sharpenRadius", "detail.sharpenDetail", "detail.sharpenMasking"])
                        subheading("Noise Reduction")
                        namedRows(["detail.nrLuminance", "detail.nrDetail", "detail.nrContrast", "detail.nrColor", "detail.nrColorDetail", "detail.nrColorSmoothness"])
                    }
                    section("Optics", id: "optics") {
                        Toggle("Remove Chromatic Aberration", isOn: Binding(get: { session.removeCA }, set: { value in
                            Task { await session.command("develop.merge", params: ["settings": ["optics": ["remove_ca": value]]]) }
                        })).foregroundStyle(session.removeCA ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                        Toggle("Enable Lens Corrections", isOn: Binding(get: { session.lensCorrections }, set: { value in
                            Task { await session.command("develop.merge", params: ["settings": ["optics": ["lens_profile": value]]]) }
                        })).foregroundStyle(session.lensCorrections ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                        if session.lensCorrections {
                            if !session.embeddedLens { Text("No lens data embedded in this file.").font(.caption).foregroundStyle(.secondary) }
                            namedRows(["optics.profileDistortion", "optics.profileVignetting"]).disabled(!session.embeddedLens)
                        }
                        subheading("Manual")
                        namedRows(["optics.distortion", "optics.vignetting", "optics.vignettingMidpoint"])
                        inlineTool("Defringe", icon: "LightCraft-Picker") {
                            namedRows(["optics.defringePurple", "optics.defringePurpleHueLo", "optics.defringePurpleHueHi", "optics.defringeGreen", "optics.defringeGreenHueLo", "optics.defringeGreenHueHi"])
                            subheading("Lateral Chromatic Aberration")
                            namedRows(["optics.caRed", "optics.caBlue"])
                        }
                    }
                    section("Calibration", id: "calibration") {
                        subheading("Shadows")
                        namedRows(["calibration.shadowsTint"])
                        ForEach([("Red Primary", "red"), ("Green Primary", "green"), ("Blue Primary", "blue")], id: \.1) { title, key in
                            subheading(title)
                            namedRows(["calibration.\(key)Hue", "calibration.\(key)Sat"])
                        }
                    }
                    if session.busy { ProgressView() }
                    if let error = session.error { Text(error).foregroundStyle(.red).font(.footnote) }
                }.padding(isPadStyle ? 14 : 20)
            }.scrollDisabled(dragging)
            .contentMargins(.bottom, isPadStyle ? 28 : 0, for: .scrollContent)
            // A gap and a short fade, so controls scroll out softly under the tab bar.
            .padding(.top, isPadStyle ? 6 : 0)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: isPadStyle ? 18 : 0)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: isPadStyle ? 28 : 0)
                }
            }
        }
        .lightCraftPanelContent(iPadStyle: isPadStyle).buttonStyle(.plain)
        .disabled(model.isShowingBefore || !model.isPhotoOpen)
        .task { await session.load() }
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging || childBusy.values.contains(true)))
        .onChange(of: pointColor.picking) { _, picking in
            if picking { whiteBalancePicking = false }
            onColorPicker(picking ? pointColor : nil)
        }
        .onChange(of: model.undoStack.last) { _, _ in Task { await session.load() } }
        .onDisappear { onColorPicker(nil); onWhiteBalancePicker(nil) }
    }
    /// inlineTool expands a child inside the same themed scrolling column.
    private func inlineTool<Content: View>(_ title: String, icon: String, changed: Bool = false, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup {
            content()
                .environment(\.editorToolEmbedded, true)
                .environment(\.editorToolDocked, true)
                .environment(\.editorToolBusy, Binding(get: { childBusy[title] ?? false }, set: { childBusy[title] = $0 }))
                .padding(.vertical, 8)
                .onDisappear { Task { await session.load() } }
        } label: {
            Label(title, lightCraftIcon: icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(changed ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label).frame(minHeight: 40)
        }
        .padding(.horizontal, isPadStyle ? 12 : 8)
        .background(isPadStyle ? .clear : LightCraftPanelStyle.inset, in: .rect(cornerRadius: 6))
        .modifier(PadCardSurface(enabled: isPadStyle))
    }
    @ViewBuilder private func treatmentChip(_ title: String, on: Bool) -> some View {
        if isPadStyle {
            Text(title).font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Color.black : LightCraftPanelStyle.text)
                .padding(.horizontal, 14).frame(minHeight: 32)
                .background {
                    if on { Capsule().fill(LightCraftPanelStyle.highlight) }
                    else { Capsule().fill(.clear).lightCraftCardSurface(cornerRadius: 16) }
                }
                .contentShape(.capsule)
        } else {
            Text(title).foregroundStyle(on ? Color.accentColor : LightCraftPanelStyle.label)
        }
    }
    /// sectionChanged lights the amber dot beside a section title when any of its controls moved.
    private func sectionChanged(_ id: String) -> Bool {
        let prefixes = id == "effects" ? ["effects.", "vignette.", "grain."] : [id + "."]
        if id == "color" && session.whiteBalanceMode != "asShot" { return true }
        return session.controls.contains { control in
            prefixes.contains { control.id.hasPrefix($0) }
                && LightCraftPanelStyle.isChanged(session.values[control.id] ?? control.value, from: control.defaultValue)
        }
    }
    private var whiteBalanceSliders: some View {
        ForEach([DevelopAdjustmentKind.temperature, .tint], id: \.self) { kind in
            let stored = model.values[kind] ?? kind.defaultValue
            let relative = kind == .temperature ? min(100, max(-100, (1_000_000 / 6500.0 - 1_000_000 / max(1, stored)) / 0.8)) : min(100, max(-100, stored))
            let storedDefault = model.defaultValue(of: kind)
            let relativeDefault = kind == .temperature ? min(100, max(-100, (1_000_000 / 6500.0 - 1_000_000 / max(1, storedDefault)) / 0.8)) : min(100, max(-100, storedDefault))
            VStack(spacing: 3) {
                HStack { Text(kind == .temperature ? "Temp" : "Tint"); Spacer(); LightCraftNumberButton(title: kind == .temperature ? "Temp" : "Tint", value: relative, range: -100...100, step: 1) { number in
                    let stored = kind == .temperature ? 1_000_000 / (1_000_000 / 6500.0 - number * 0.8) : number
                    model.beginDrag(kind)
                    Task.immediate { await model.drag(kind, to: stored); await model.endDrag(kind) }
                } }
                    .foregroundStyle(LightCraftPanelStyle.isChanged(relative, from: relativeDefault) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSlider(value: Binding(get: { relative }, set: { value in
                    let kelvin = kind == .temperature ? 1_000_000 / (1_000_000 / 6500.0 - value * 0.8) : value
                    Task.immediate { await model.drag(kind, to: kelvin) }
                }), in: -100...100, step: 1, controlID: kind.rawValue, defaultValue: relativeDefault) { editing in
                    dragging = editing
                    if editing { model.beginDrag(kind) } else { Task.immediate { await model.endDrag(kind) } }
                }.accessibilityLabel(kind == .temperature ? "Temp" : "Tint")
            }
            .contextMenu { Button("Reset") { Task { await model.reset(kind) } } }
        }
    }
    private var whiteBalanceTitle: String { session.whiteBalanceMode == "asShot" ? "As Shot" : session.whiteBalanceMode.capitalized }
    /// subheading names a group of rows; on iPad it outranks the row labels beneath it.
    private func subheading(_ title: String) -> some View {
        Text(title).font(.system(size: isPadStyle ? 16 : 13, weight: isPadStyle ? .bold : .semibold))
            .foregroundStyle(isPadStyle ? Color.white : LightCraftPanelStyle.label)
            .padding(.top, isPadStyle ? 10 : 6)
    }
    private func tool(_ title: String, _ tool: EditorDockTool) -> some View {
        Button { openTool(tool) } label: { HStack { Text(title); Spacer(); Image(lightCraftIcon: "LightCraft-ChevronRight") } }
            .buttonStyle(.plain).frame(minHeight: 32)
    }
    private func rows(_ prefixes: [String]) -> some View {
        ForEach(session.matching(prefixes)) { control in controlRow(control) }
    }
    private func namedRows(_ ids: [String]) -> some View {
        ForEach(ids, id: \.self) { id in
            if let control = session.controls.first(where: { $0.id == id }) {
                controlRow(control)
                    .disabled((id.hasPrefix("optics.defringePurpleHue") && (session.values["optics.defringePurple"] ?? 0) == 0)
                        || (id.hasPrefix("optics.defringeGreenHue") && (session.values["optics.defringeGreen"] ?? 0) == 0))
            }
        }
    }
    @ViewBuilder private func controlRow(_ control: NativeDevelopControl) -> some View {
        if let kind = DevelopAdjustmentKind(rawValue: control.id) {
            LightCraftCoreSliderRow(model: model, kind: kind, value: model.values[kind] ?? kind.defaultValue,
                                    defaultValue: model.defaultValue(of: kind), onEditingChanged: { dragging = $0 }).equatable()
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(control.label); Spacer()
                    LightCraftNumberButton(title: control.label, value: session.values[control.id] ?? control.value,
                                           range: control.min...control.max, step: control.step, decimals: control.step < 1 ? 2 : 0) { number in
                        session.values[control.id] = number
                        Task { await session.apply(control) }
                    }.disabled(session.busy)
                }.foregroundStyle(LightCraftPanelStyle.isChanged(session.values[control.id] ?? control.value, from: control.defaultValue) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSlider(value: Binding(get: { session.values[control.id] ?? control.value }, set: { session.values[control.id] = $0 }), in: control.min...control.max, step: control.step, controlID: control.id, defaultValue: control.defaultValue) { editing in
                    dragging = editing
                    if !editing { Task { await session.apply(control) } }
                }.accessibilityLabel(control.label).disabled(session.busy)
            }.contextMenu {
                Button("Reset \(control.label)") { session.values[control.id] = control.defaultValue; Task { await session.apply(control) } }
            }
        }
    }
    private func section<Content: View>(_ title: String, id: String, @ViewBuilder content: @escaping () -> Content) -> some View {
        DisclosureGroup(isExpanded: Binding(get: { openSections.contains(title) }, set: { expanded in
            if expanded { if soloMode { openSections = [title] } else { openSections.insert(title) } }
            else { openSections.remove(title) }
        })) {
            VStack(alignment: .leading, spacing: 12) { content() }.padding(.top, isPadStyle ? 6 : 10).padding(.bottom, 10)
        } label: {
            HStack(spacing: 6) {
                Text(title).font(.system(size: isPadStyle ? 20 : 15, weight: isPadStyle ? .bold : .semibold))
                    .foregroundStyle(isPadStyle ? Color.white : LightCraftPanelStyle.label)
                if isPadStyle && sectionChanged(id) {
                    Circle().fill(LightCraftPanelStyle.highlight).frame(width: 6, height: 6).accessibilityLabel("Edited")
                }
                Spacer()
                Button {
                    Task { await session.command("develop.sectionEnabled", params: SectionToggle(section: id, enabled: session.disabledSections.contains(id))) }
                } label: {
                    Image(lightCraftIcon: session.disabledSections.contains(id) ? "LightCraft-EyeOff" : "LightCraft-Eye")
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Toggle \(title)").disabled(session.busy)
                .padding(.trailing, isPadStyle ? 14 : 20)
            }
        }
        .padding(.horizontal, isPadStyle ? 14 : 0).padding(.vertical, isPadStyle ? 4 : 0)
        .modifier(PadCardSurface(enabled: isPadStyle))
        .contextMenu {
            Toggle("Solo Mode", isOn: $soloMode)
            Button("Reset \(title)") { Task { await session.command("develop.resetSection", params: ["section": id]) } }
        }
    }
    nonisolated private struct SectionToggle: Encodable, Sendable { let section: String; let enabled: Bool }
}

/// The value boundary prevents a change to one dictionary entry from invalidating every slider.
private struct LightCraftCoreSliderRow<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View, Equatable {
    let model: EditorViewModel<Engine, Importer>
    let kind: DevelopAdjustmentKind
    let value: Double
    let defaultValue: Double
    let onEditingChanged: (Bool) -> Void
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.value == rhs.value && lhs.defaultValue == rhs.defaultValue
    }
    var body: some View {
        AdjustmentSlider(kind: kind, value: value, defaultValue: defaultValue,
                         onDragValue: { value in Task.immediate { await model.drag(kind, to: value) } },
                         onEditingChanged: { editing in
                             onEditingChanged(editing)
                             if editing { model.beginDrag(kind) }
                             else { Task.immediate { await model.endDrag(kind) } }
                         }, onCommit: { value in
                             Task.immediate { model.beginDrag(kind); await model.drag(kind, to: value); await model.endDrag(kind) }
                         }, onNudge: { delta in Task.immediate { await model.nudge(kind, by: delta) } },
                         onReset: { Task.immediate { await model.reset(kind) } }, isCompact: true)
            .equatable()
    }
}

/// PadCardSurface applies the raised iPad card only where the iPad design is in use.
struct PadCardSurface: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.lightCraftCardSurface() } else { content }
    }
}
