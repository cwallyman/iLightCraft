import SwiftUI

struct ProfilesPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: ProfileEditorSession<Engine, Importer>
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var dragging = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked

    init(model: EditorViewModel<Engine, Importer>) {
        _session = State(initialValue: ProfileEditorSession(model: model))
    }
    private func close() {
        if let closeDock { closeDock() } else { dismiss() }
    }
    var body: some View {
        EditorToolPresentation(title: "Profiles", header: { EmptyView() }) {
            EditorPanelScroll {
                VStack(alignment: .leading, spacing: 16) {
                    if !isDocked, let preview = session.preview {
                        Image(uiImage: preview).resizable().aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 180).accessibilityLabel("Photo with selected profile")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Current: \(session.currentName)").font(.headline).foregroundStyle(session.selectedID == "lc.color" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
                        HStack {
                            Text("Amount")
                            Spacer()
                            LightCraftNumberButton(title: "Profile Amount", value: session.amount, range: 0...200, step: 1, suffix: "%") { number in
                                session.amount = number; Task { await session.commitAmount() }
                            }.disabled(!session.loaded || session.busy || session.model.isShowingBefore)
                        }.foregroundStyle(LightCraftPanelStyle.isChanged(session.amount, from: 100) ? LightCraftPanelStyle.changed : LightCraftPanelStyle.label)
                        LightCraftSlider(value: $session.amount, in: 0...200, step: 1, defaultValue: 100, onEditingChanged: { editing in
                            dragging = editing
                            if !editing { Task { await session.commitAmount() } }
                        })
                        .accessibilityLabel("Profile amount")
                        .disabled(!session.loaded || session.busy || session.model.isShowingBefore)
                        Text("Release to apply the amount.").font(.caption).foregroundStyle(.secondary)
                        Button("Reset Profile to Color") { Task { await session.reset() } }
                            .disabled(!session.loaded || session.busy || dragging || session.model.isShowingBefore)
                    }
                    TextField("Search profiles", text: $query).textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Search profiles")
                    Toggle("Favorites only", isOn: $favoritesOnly)
                    if let menu = session.menu {
                        if !favoritesOnly && query.isEmpty && !menu.recent.isEmpty {
                            profileGroup("Recent", profiles: menu.recent)
                        }
                        let groups = menu.groups.filter { !filtered($0.profiles).isEmpty }
                        if groups.isEmpty { Text("No matching profiles").foregroundStyle(.secondary) }
                        ForEach(groups.indices, id: \.self) { index in
                            profileGroup(groups[index].name, profiles: filtered(groups[index].profiles))
                        }
                    }
                    if session.busy { ProgressView("Updating profile…") }
                    if let error = session.error ?? session.model.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .scrollDisabled(dragging)
            .task { await session.load(showsPreview: !isDocked) }
            .interactiveDismissDisabled(session.busy || dragging)
        }
        .preferredColorScheme(.dark)
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
    }
    private func filtered(_ profiles: [NativeProfile]) -> [NativeProfile] {
        profiles.filter { profile in
            (!favoritesOnly || profile.favorite)
                && (query.isEmpty || (profile.name + " " + profile.group).localizedCaseInsensitiveContains(query))
        }
    }
    private func profileGroup(_ title: String, profiles: [NativeProfile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(profiles) { profile in
                HStack(spacing: 8) {
                    Button {
                        Task { await session.select(profile) }
                    } label: {
                        HStack {
                            Image(lightCraftIcon: session.selectedID == profile.id ? "LightCraft-Check" : "LightCraft-Circle")
                                .foregroundStyle(session.selectedID == profile.id ? Color.accentColor : .secondary)
                            Text(profile.name).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .contentShape(Rectangle()).frame(minHeight: 40)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(profile.name)
                    .accessibilityValue(session.selectedID == profile.id ? "Selected" : "")
                    Button(profile.favorite ? "Remove favorite" : "Favorite", lightCraftIcon: profile.favorite ? "LightCraft-StarFilled" : "LightCraft-Star") {
                        Task { await session.favorite(profile) }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .foregroundStyle(profile.favorite ? Color.accentColor : .secondary)
                    .help(profile.favorite ? "Remove favorite" : "Favorite")
                }
                .disabled(session.busy || dragging || !session.loaded || session.model.isShowingBefore)
            }
        }
    }
}
