import SwiftUI

/// The desktop keeps lens correction in Edit and perspective controls in Crop's Geometry section.
struct OpticsPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: AdvancedColorSession<Engine, Importer>
    var geometryOnly = false
    var beforeGeometryEdit: (@MainActor () async -> Bool)? = nil
    @State private var dragging = false
    var body: some View {
        EditorToolPresentation(title: geometryOnly ? "Geometry" : "Optics", header: { EmptyView() }) {
            EditorPanelScroll {
                VStack(alignment: .leading, spacing: 14) {
                    if geometryOnly { geometry } else { optics }
                    if session.busy { ProgressView("Updating photo…") }
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(20)
            }
            .scrollDisabled(dragging)
            .task { await session.load() }
        }
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
    }
    private var optics: some View {
        Group {
            Toggle("Remove Chromatic Aberration", isOn: Binding(get: { session.removeCA }, set: { value in
                Task { await session.option("optics", "remove_ca", value) }
            })).foregroundStyle(session.removeCA ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label).disabled(session.busy)
            Toggle("Enable Lens Corrections", isOn: Binding(get: { session.lensProfile }, set: { value in
                Task { await session.option("optics", "lens_profile", value) }
            })).foregroundStyle(session.lensProfile ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label).disabled(session.busy)
            if session.lensProfile {
                if !session.embeddedLens { Text("No lens data embedded in this file.").font(.caption).foregroundStyle(.secondary) }
                rows(["optics.profileDistortion", "optics.profileVignetting"]).disabled(!session.embeddedLens)
            }
            Text("Manual").font(.system(size: 13, weight: .semibold))
            rows(["optics.distortion", "optics.vignetting", "optics.vignettingMidpoint"])
            DisclosureGroup("Defringe") {
                rows(["optics.defringePurple", "optics.defringePurpleHueLo", "optics.defringePurpleHueHi", "optics.defringeGreen", "optics.defringeGreenHueLo", "optics.defringeGreenHueHi"])
                Text("Lateral Chromatic Aberration").font(.system(size: 13, weight: .semibold))
                rows(["optics.caRed", "optics.caBlue"])
            }
        }
    }
    private var geometry: some View {
        Group {
            Text("Upright").font(.system(size: 13, weight: .semibold))
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 6) {
                ForEach(["off", "auto", "guided", "level", "vertical", "full"], id: \.self) { mode in
                    Button(mode.capitalized) {
                        editGeometry { if mode == "guided" { await session.beginGuides() } else { await session.setUpright(mode) } }
                    }
                    .buttonStyle(.bordered)
                    .tint(session.upright == mode ? Color.accentColor : .gray)
                }
            }.disabled(session.busy || dragging)
            if session.upright != "off" && session.upright != "guided" {
                Button("Update") { editGeometry { await session.setUpright(session.upright) } }.disabled(session.busy)
            }
            if session.guiding {
                Text("\(session.guideLines.count) of 4 guides. Draw lines that should be vertical or horizontal.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Apply Guides") { editGeometry { await session.applyGuides() } }.disabled(session.busy || session.guideLines.count < 2)
                    Button("Clear Guides") { session.guideLines = []; session.guideStroke = [] }
                }
                Button("Cancel Guides") { session.guiding = false; session.guideLines = []; session.guideStroke = [] }
            } else if session.upright == "guided" {
                Button("Draw Guides") { editGeometry { await session.beginGuides() } }
            }
            Toggle("Constrain Crop", isOn: Binding(get: { session.constrainCrop }, set: { value in
                editGeometry { await session.option("geometry", "constrain_crop", value) }
            })).foregroundStyle(session.constrainCrop ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label).disabled(session.busy)
            numericRows(session.matching("geometry."))
        }
    }
    private func editGeometry(_ operation: @escaping @MainActor () async -> Void) {
        Task {
            if let beforeGeometryEdit, !(await beforeGeometryEdit()) { return }
            await operation()
        }
    }
    private func rows(_ ids: [String]) -> some View {
        numericRows(ids.compactMap { id in session.controls.first { $0.id == id } })
    }
    private func numericRows(_ controls: [NativeDevelopControl]) -> some View {
        ForEach(controls) { control in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(control.label); Spacer()
                    LightCraftNumberButton(title: control.label, value: session.values[control.id] ?? control.value,
                                           range: control.min...control.max, step: control.step, decimals: control.step < 1 ? 2 : 0) { number in
                        session.setDraft(control.id, number)
                        if geometryOnly { editGeometry { await session.apply([control.id]) } } else { Task { await session.apply([control.id]) } }
                    }.disabled(session.busy || !session.loaded)
                }.foregroundStyle(LightCraftPanelStyle.isChanged(session.values[control.id] ?? control.value, from: control.defaultValue) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                LightCraftSlider(value: Binding(get: { session.values[control.id] ?? control.value }, set: { session.setDraft(control.id, $0) }), in: control.min...control.max, step: control.step, controlID: control.id, defaultValue: control.defaultValue) { active in
                    dragging = active
                    if !active {
                        if geometryOnly { editGeometry { await session.apply([control.id]) } }
                        else { Task { await session.apply([control.id]) } }
                    }
                }.accessibilityLabel(control.label).disabled(session.busy || !session.loaded)
            }
        }
    }
}
