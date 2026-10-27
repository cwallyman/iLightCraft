import SwiftUI
import UniformTypeIdentifiers

struct PresetVersionPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PresetVersionSession<Engine, Importer>
    let versionsMode: Bool
    var historyMode = false
    var appExtras = false
    var openBatch: (() -> Void)? = nil
    @State private var automaticVersions = false
    @State private var collapsedPresetGroups: Set<String> = []
    @State private var creatingPreset = false
    @State private var adjustingAmount = false
    @State private var showsPresetSearch = false
    @State private var editingPreset: PresetVersionSession<Engine, Importer>.Preset?
    @State private var presetEditName = ""
    @State private var deletingPreset: PresetVersionSession<Engine, Importer>.Preset?
    @State private var clearsHistory = false
    @State private var importing = false
    @State private var sharing = false
    @State private var deleteIndex: Int?
    @Environment(\.editorToolClose) private var close
    var body: some View {
        EditorToolPresentation(title: historyMode ? "History" : (versionsMode ? "Versions" : (appExtras ? "Presets & Batch Edits" : "Presets")), header: {
            if !versionsMode && !historyMode && !appExtras {
                presetOptions
                Button("Create Preset…", lightCraftIcon: "LightCraft-Plus") { creatingPreset = true }
                    .labelStyle(.iconOnly).help("Create Preset…").disabled(session.busy)
            } else if appExtras {
            Button("Undo", lightCraftIcon: "LightCraft-Rotate") { Task { await session.undo() } }
                .disabled(!session.model.canUndo || session.busy)
            Button("Redo", lightCraftIcon: "LightCraft-RotateClockwise") { Task { await session.undo(redo: true) } }
                .disabled(!session.model.canRedo || session.busy)
            Button("Done") { close?() }.disabled(session.busy)
            }
        }) {
            VStack(spacing: 0) {
            if !versionsMode && !historyMode && !appExtras, session.appliedPresetID != nil {
                presetAmount
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !historyMode && (versionsMode || appExtras) {
                        TextField(versionsMode ? "Version / copy name" : "Preset name", text: $session.name).textFieldStyle(.roundedBorder)
                    }
                    if historyMode { history } else if versionsMode { versions } else if appExtras { presets } else { groupedPresets }
                    if session.busy { ProgressView("Working…") }
                    if !session.status.isEmpty { Text(session.status).font(.footnote).foregroundStyle(.secondary) }
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(16)
            }
            .task { await session.load(includePhotos: versionsMode || appExtras) }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.item]) { result in
                switch result {
                case .success(let url): Task { await session.importPreset(url) }
                case .failure(let error): session.error = error.localizedDescription
                }
            }
            .sheet(isPresented: $sharing) {
                if let file = session.exportedFile { PhotoShareSheet(files: [file]) }
            }
            .confirmationDialog("Delete this saved version?", isPresented: Binding(get: { deleteIndex != nil }, set: { if !$0 { deleteIndex = nil } })) {
                Button("Delete Version", role: .destructive) {
                    if let index = deleteIndex { Task { await session.deleteVersion(index) } }
                    deleteIndex = nil
                }
            }
            }
        }
        .sheet(isPresented: $creatingPreset) { createPresetSheet }
        .alert("Rename Preset", isPresented: Binding(get: { editingPreset != nil }, set: { if !$0 { editingPreset = nil } })) {
            TextField("Preset name", text: $presetEditName)
            Button("Cancel", role: .cancel) { editingPreset = nil }
            Button("Rename") {
                if let preset = editingPreset { Task { await session.managePreset(preset, command: "preset.rename", value: presetEditName) } }
                editingPreset = nil
            }
        }
        .confirmationDialog("Delete this user preset?", isPresented: Binding(get: { deletingPreset != nil }, set: { if !$0 { deletingPreset = nil } })) {
            Button("Delete Preset", role: .destructive) {
                if let preset = deletingPreset { Task { await session.managePreset(preset, command: "preset.delete") } }
                deletingPreset = nil
            }
        }
        .confirmationDialog("Clear History?", isPresented: $clearsHistory) {
            Button("Clear History", role: .destructive) { Task { await session.clearHistory() } }
        } message: { Text("Keeps the current settings as the only history step.") }
        .modifier(EditorToolBusyReporter(busy: session.busy || adjustingAmount))
    }
    private var presetAmount: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Amount")
                Spacer()
                LightCraftNumberButton(title: "Preset Amount", value: session.amount, range: 0...200, step: 1) { number in
                    session.amount = number; Task { await session.updatePresetAmount() }
                }
            }
            .font(.system(size: 15)).foregroundStyle(LightCraftPanelStyle.isChanged(session.amount, from: 100) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
            LightCraftSlider(value: $session.amount, in: 0...200, step: 1, defaultValue: 100) { editing in
                adjustingAmount = editing
                if !editing { Task { await session.updatePresetAmount() } }
            }
            .tint(.secondary)
            .accessibilityLabel("Preset amount")
            .accessibilityValue("\(Int(session.amount)) percent")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: session.amount = min(200, session.amount + 5)
                case .decrement: session.amount = max(0, session.amount - 5)
                @unknown default: return
                }
                Task { await session.updatePresetAmount() }
            }
            .disabled(session.busy)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .accessibilityIdentifier("selected-preset-amount")
    }

    private var presetOptions: some View {
        Menu("More preset options", lightCraftIcon: "LightCraft-More") {
            if let openBatch { Button("Batch Editing", action: openBatch) }
            Button("Reset") { Task { await session.resetPreset() } }
                .disabled(session.appliedPresetID == nil || adjustingAmount)
            Divider()
            Toggle("Search Presets", isOn: $showsPresetSearch)
            Toggle("Favorites Only", isOn: $session.favoritesOnly)
            Divider()
            Button("Expand All Groups") { collapsedPresetGroups = [] }
            Button("Collapse All Groups") { collapsedPresetGroups = Set(session.presetGroups.map(\.name)) }
            Divider()
            Button("Import Presets…") { importing = true }
            Button("Export User Presets…") { Task { await session.exportPresets(); sharing = session.exportedFile != nil } }
                .disabled(!session.presets.contains { !$0.builtin })
        }
        .labelStyle(.iconOnly).help("More preset options").disabled(session.busy)
    }

    private var groupedPresets: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if showsPresetSearch {
                TextField("Search presets", text: $session.query).textFieldStyle(.roundedBorder).padding(.bottom, 10)
            }
            ForEach(session.presetGroups) { group in
                Button {
                    if collapsedPresetGroups.contains(group.name) { collapsedPresetGroups.remove(group.name) }
                    else { collapsedPresetGroups.insert(group.name) }
                } label: {
                    HStack(spacing: 8) {
                        Image(lightCraftIcon: collapsedPresetGroups.contains(group.name) ? "LightCraft-ChevronRight" : "LightCraft-ChevronDown")
                            .frame(width: 16)
                        Text(group.name).font(.system(size: 15, weight: .semibold))
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .accessibilityValue(collapsedPresetGroups.contains(group.name) ? "Collapsed" : "Expanded")
                if !collapsedPresetGroups.contains(group.name) {
                    ForEach(group.items) { preset in
                        Button {
                            session.amount = 100
                            Task { await session.applyPreset(preset) }
                        } label: {
                            HStack {
                                Text(preset.name).font(.system(size: 14)).multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                if preset.favorite { Image(lightCraftIcon: "LightCraft-StarFilled").foregroundStyle(.yellow).accessibilityLabel("Favorite") }
                            }
                            .padding(.leading, 24).padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                            .contentShape(.rect)
                            .background(session.appliedPresetID == preset.id ? LightCraftPanelStyle.inset : .clear, in: .rect(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(session.appliedPresetID == preset.id ? Color.accentColor : LightCraftPanelStyle.label)
                        .accessibilityIdentifier("preset-\(preset.id)")
                        .contextMenu {
                            Button(preset.favorite ? "Remove from Favorites" : "Add to Favorites") { Task { await session.favorite(preset) } }
                            if !preset.builtin {
                                Button("Update with Current Settings") { Task { await session.managePreset(preset, command: "preset.update") } }
                                Button("Rename…") { presetEditName = preset.name; editingPreset = preset }
                                Menu("Move to Group") {
                                    ForEach(session.presetGroups.filter { $0.name != preset.group }) { group in
                                        Button(group.name) { Task { await session.managePreset(preset, command: "preset.move", value: group.name) } }
                                    }
                                }
                                Button("Delete Preset…", role: .destructive) { deletingPreset = preset }
                            }
                        }
                    }
                }
            }
            if session.presets.isEmpty && !session.busy { Text("No presets available").foregroundStyle(.secondary).padding(.vertical) }
        }
        .disabled(session.busy)
    }

    private var createPresetSheet: some View {
        NavigationStack {
            LightCraftMenuList {
                LightCraftMenuSection("Preset") {
                    TextField("Preset name", text: $session.name)
                    TextField("Group", text: $session.presetGroupName)
                }
                LightCraftMenuSection("Settings to Include") {
                    ForEach(NativeSettingsGroup.allCases) { group in
                        Toggle(group.title, isOn: Binding(get: { session.groups.contains(group) }, set: { enabled in
                            if enabled { session.groups.insert(group) } else { session.groups.remove(group) }
                        }))
                    }
                }
                if let error = session.error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Create Preset")
                    .toolbarBackground(LightCraftPanelStyle.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { creatingPreset = false }.disabled(session.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task { await session.createPreset(); if session.error == nil { creatingPreset = false } }
                    }.disabled(!session.validName || session.presetGroupName.count > 120 || session.groups.isEmpty || session.busy)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(session.busy)
    }

    private var presets: some View {
        VStack(alignment: .leading, spacing: 16) {
            DisclosureGroup("Settings to save / copy / paste") {
                ForEach(NativeSettingsGroup.allCases) { group in
                    Toggle(group.title, isOn: Binding(get: { session.groups.contains(group) }, set: { value in
                        if value { session.groups.insert(group) } else { session.groups.remove(group) }
                    }))
                }
                Button("Default Groups") { session.groups = NativeSettingsGroup.defaults }
            }
            Button("Save Current Settings as Preset") { Task { await session.createPreset() } }
                .disabled(!session.validName || session.groups.isEmpty)
            HStack {
                Button("Copy Settings") { Task { await session.copySettings() } }
                Button("Paste to This Photo") { Task { await session.pasteSettings(batch: false) } }
            }.disabled(session.groups.isEmpty)
            TextField("Search presets", text: $session.query).textFieldStyle(.roundedBorder)
            Toggle("Favorites only", isOn: $session.favoritesOnly)
            HStack {
                Text("Preset amount")
                Spacer()
                LightCraftNumberButton(title: "Preset Amount", value: session.amount, range: 0...200, step: 1, suffix: "%") { session.amount = $0 }
            }.foregroundStyle(LightCraftPanelStyle.isChanged(session.amount, from: 100) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
            LightCraftSlider(value: $session.amount, in: 0...200, step: 1, defaultValue: 100).accessibilityLabel("Preset amount")
            ForEach(session.presets.filter { (!session.favoritesOnly || $0.favorite) && (session.query.isEmpty || ($0.name + " " + $0.group).localizedCaseInsensitiveContains(session.query)) }) { preset in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(preset.name) { Task { await session.applyPreset(preset) } }
                        Spacer()
                        Button(preset.favorite ? "Unfavorite" : "Favorite", lightCraftIcon: preset.favorite ? "LightCraft-StarFilled" : "LightCraft-Star") { Task { await session.favorite(preset) } }
                            .labelStyle(.iconOnly)
                    }
                    Text(preset.group).font(.caption).foregroundStyle(.secondary)
                    if !session.selected.isEmpty {
                        Button("Apply to \(session.selected.count) Other Photos") { Task { await session.applyPreset(preset, batch: true) } }
                            .font(.caption)
                    }
                }.padding(.vertical, 4)
            }
            HStack {
                Button("Import .lcpreset") { importing = true }
                Button("Export User Presets") { Task { await session.exportPresets(); sharing = session.exportedFile != nil } }
            }
            Divider()
            if appExtras {
            DisclosureGroup("Other imported photos: \(session.selected.count) selected") {
                Text("Batch edits affect local catalog edits, not original files or Photos assets. This photo is excluded. Choose up to 20.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(session.photos.filter { $0.id != session.model.openPhoto?.rawValue }) { photo in
                    Button { session.toggle(photo.id) } label: {
                        Label(photo.name, lightCraftIcon: session.selected.contains(photo.id) ? "LightCraft-Check" : "LightCraft-Circle")
                    }
                }
                if session.photos.count < session.total && session.photos.count < 1000 {
                    Button("Load More Photos") { Task { await session.loadMore() } }
                }
                Button("Paste to Selected Other Photos") { Task { await session.pasteSettings(batch: true) } }
                    .disabled(session.selected.isEmpty || session.groups.isEmpty)
                Button("Undo Last Other-Photo Batch") { Task { await session.undoBatch() } }.disabled(!session.canUndoBatch)
                Button("Redo Other-Photo Batch") { Task { await session.undoBatch(redo: true) } }.disabled(!session.canRedoBatch)
                Text("Batch undo/redo is available in this panel until it closes. Each photo also retains its engine history.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            }
        }.disabled(session.busy)
    }
    private var versions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Create Version") { Task { await session.createVersion() } }
            Picker("Versions", selection: $automaticVersions) {
                Text("Named").tag(false); Text("Auto").tag(true)
            }.pickerStyle(.segmented)
            ForEach(session.versions.indices.reversed().filter { (session.versions[$0].auto ?? false) == automaticVersions }, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.versions[index].name).font(.headline)
                    Text(session.versions[index].created).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Restore") { Task { await session.restoreVersion(index) } }
                        Button("Compare") { Task { await session.reference(version: index) } }
                        Button("Rename") { Task { await session.renameVersion(index) } }.disabled(!session.validName)
                    }
                    Button("Update with Current Settings") { Task { await session.updateVersion(index) } }
                    Button("Set as Before") { Task { await session.setBefore(version: index) } }
                    Button("Delete Version", role: .destructive) { deleteIndex = index }
                }.padding(.vertical, 6)
            }
            if session.referenceImage != nil { Button("Close Reference") { session.clearReference() } }
            DisclosureGroup("Compare with another imported photo") {
                ForEach(session.photos.filter { $0.id != session.model.openPhoto?.rawValue }) { photo in
                    Button(photo.name) { Task { await session.reference(photo: photo) } }
                }
                if session.photos.count < session.total && session.photos.count < 1000 {
                    Button("Load More Photos") { Task { await session.loadMore() } }
                }
            }
        }.disabled(session.busy)
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Persistent history").font(.headline)
            ForEach(Array(session.history.indices.reversed()), id: \.self) { index in
                Button("\(index + 1). \(session.history[index])") { Task { await session.restoreHistory(index) } }
                    .multilineTextAlignment(.leading)
                    .contextMenu {
                        Button("Copy History Step Settings to Before") { Task { await session.setBefore(history: index) } }
                        Button("Create Version from Step") { Task { await session.versionFromHistory(index) } }
                        Button("Clear History", role: .destructive) { clearsHistory = true }
                    }
            }
        }.disabled(session.busy)
    }
}
