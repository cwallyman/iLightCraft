import SwiftUI
import UniformTypeIdentifiers

struct PresetVersionPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PresetVersionSession<Engine, Importer>
    let versionsMode: Bool
    @State private var importing = false
    @State private var sharing = false
    @State private var deleteIndex: Int?
    @Environment(\.editorToolClose) private var close
    var body: some View {
        EditorToolPresentation(title: versionsMode ? "Versions & History" : "Presets & Batch Edits", header: {
            Button("Undo", systemImage: "arrow.uturn.backward") { Task { await session.undo() } }
                .disabled(!session.model.canUndo || session.busy)
            Button("Redo", systemImage: "arrow.uturn.forward") { Task { await session.undo(redo: true) } }
                .disabled(!session.model.canRedo || session.busy)
            Button("Done") { close?() }.disabled(session.busy)
        }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField(versionsMode ? "Version / copy name" : "Preset name", text: $session.name).textFieldStyle(.roundedBorder)
                    if versionsMode { versions } else { presets }
                    if session.busy { ProgressView("Working…") }
                    if !session.status.isEmpty { Text(session.status).font(.footnote).foregroundStyle(.secondary) }
                    if let error = session.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.padding(16)
            }
            .task { await session.load() }
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
        .modifier(EditorToolBusyReporter(busy: session.busy))
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
            Text("Preset amount: \(Int(session.amount))%")
            Slider(value: $session.amount, in: 0...200, step: 1).accessibilityLabel("Preset amount")
            ForEach(session.presets.filter { (!session.favoritesOnly || $0.favorite) && (session.query.isEmpty || ($0.name + " " + $0.group).localizedCaseInsensitiveContains(session.query)) }) { preset in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(preset.name) { Task { await session.applyPreset(preset) } }
                        Spacer()
                        Button(preset.favorite ? "Unfavorite" : "Favorite", systemImage: preset.favorite ? "star.fill" : "star") { Task { await session.favorite(preset) } }
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
            DisclosureGroup("Other imported photos: \(session.selected.count) selected") {
                Text("Batch edits affect local catalog edits, not original files or Photos assets. This photo is excluded. Choose up to 20.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(session.photos.filter { $0.id != session.model.openPhoto?.rawValue }) { photo in
                    Button { session.toggle(photo.id) } label: {
                        Label(photo.name, systemImage: session.selected.contains(photo.id) ? "checkmark.circle.fill" : "circle")
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
        }.disabled(session.busy)
    }
    private var versions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button("Save Named Version") { Task { await session.createVersion() } }.disabled(!session.validName)
            Button("Create Alternate Edit Copy") { Task { await session.virtualCopy() } }
            Text("Alternate copies share the source file and have independent local edits. They do not overwrite the source Photos item.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(session.versions.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.versions[index].name).font(.headline)
                    Text(session.versions[index].created).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Restore") { Task { await session.restoreVersion(index) } }
                        Button("Compare") { Task { await session.reference(version: index) } }
                        Button("Rename") { Task { await session.renameVersion(index) } }.disabled(!session.validName)
                    }
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
            Divider()
            Text("Persistent history").font(.headline)
            ForEach(Array(session.history.indices.reversed()), id: \.self) { index in
                Button("\(index + 1). \(session.history[index])") { Task { await session.restoreHistory(index) } }
                    .multilineTextAlignment(.leading)
            }
        }.disabled(session.busy)
    }
}
