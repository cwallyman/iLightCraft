import SwiftUI

struct ProfilesPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: ProfileEditorSession<Engine, Importer>
    @State private var query = ""
    @State private var favoritesOnly = false
    @State private var dragging = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.editorToolClose) private var closeDock
    @Environment(\.editorToolDocked) private var isDocked
    private let pad = LightCraftPanelStyle.isPad

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
                        Text("Current: \(session.currentName)").font(pad ? .system(size: 16, weight: .bold) : .headline).foregroundStyle(session.selectedID == "lc.color" ? LightCraftPanelStyle.label : LightCraftPanelStyle.changed)
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
                        if !pad { Text("Release to apply the amount.").font(.caption).foregroundStyle(.secondary) }
                        resetButton
                    }
                    if pad { padSearch } else {
                        TextField("Search profiles", text: $query).textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Search profiles")
                    }
                    Toggle("Favorites only", isOn: $favoritesOnly)
                        .tint(LightCraftPanelStyle.highlight)
                        .font(pad ? .subheadline.weight(.semibold) : .body)
                        .foregroundStyle(pad ? .white : LightCraftPanelStyle.label)
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
                .padding(pad ? 0 : 16)
                .padding(.vertical, pad ? 4 : 0)
            }
            .scrollDisabled(dragging)
            .task { await session.load(showsPreview: !isDocked) }
            .interactiveDismissDisabled(session.busy || dragging)
        }
        .preferredColorScheme(.dark)
        .modifier(EditorToolBusyReporter(busy: session.busy || dragging))
    }
    @ViewBuilder private var resetButton: some View {
        let button = Button("Reset Profile to Color") { Task { await session.reset() } }
            .disabled(!session.loaded || session.busy || dragging || session.model.isShowingBefore)
        if pad {
            button.buttonStyle(.plain).foregroundStyle(.white).lightCraftGlassButton().padding(.top, 4)
        } else {
            button
        }
    }
    /// padSearch is the iPad search field: a rounded card with a magnifying glass and a clear button.
    private var padSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.55))
            TextField("Search profiles", text: $query).foregroundStyle(.white)
                .accessibilityLabel("Search profiles")
            if !query.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") { query = "" }
                    .labelStyle(.iconOnly).buttonStyle(.plain).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .lightCraftCardSurface(cornerRadius: 14)
    }
    private func filtered(_ profiles: [NativeProfile]) -> [NativeProfile] {
        profiles.filter { profile in
            (!favoritesOnly || profile.favorite)
                && (query.isEmpty || (profile.name + " " + profile.group).localizedCaseInsensitiveContains(query))
        }
    }
    private func profileGroup(_ title: String, profiles: [NativeProfile]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(pad ? .system(size: 16, weight: .bold) : .subheadline.weight(.semibold))
                .foregroundStyle(pad ? Color.white : Color.secondary).padding(.top, pad ? 6 : 0)
            ForEach(profiles) { profile in
                let selected = session.selectedID == profile.id
                HStack(spacing: 8) {
                    Button {
                        Task { await session.select(profile) }
                    } label: {
                        HStack {
                            Image(lightCraftIcon: selected ? "LightCraft-Check" : "LightCraft-Circle")
                                .foregroundStyle(selected ? (pad ? LightCraftPanelStyle.highlight : Color.accentColor) : .secondary)
                            Text(profile.name).frame(maxWidth: .infinity, alignment: .leading)
                                .font(pad ? .subheadline.weight(.semibold) : .body)
                                .foregroundStyle(pad ? .white : LightCraftPanelStyle.label)
                        }
                        .contentShape(Rectangle()).frame(minHeight: pad ? 44 : 40)
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
                    .foregroundStyle(profile.favorite ? (pad ? LightCraftPanelStyle.highlight : Color.accentColor) : .secondary)
                    .help(profile.favorite ? "Remove favorite" : "Favorite")
                }
                .disabled(session.busy || dragging || !session.loaded || session.model.isShowingBefore)
            }
        }
    }
}
