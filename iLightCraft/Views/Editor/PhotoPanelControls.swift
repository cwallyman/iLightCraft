//
//  PhotoPanelControls.swift
//  iLightCraft
//

import SwiftUI

/// PhotoPanelControls follows LightCraft's bottom bar: views, sort, rating/flags and copy settings.
struct PhotoPanelControls<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PhotoPanelSession<Engine, Importer>
    let locked: Bool
    let chooseMode: (PhotoPanelMode) -> Void
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach([PhotoPanelMode.detail, .beforeAfter]) { mode in
                    icon(mode.title, mode.icon, selected: session.mode == mode) { chooseMode(mode) }
                }
                Divider().frame(height: 26).padding(.horizontal, 8)
                sortMenu
                Spacer(minLength: 16)
                HStack(spacing: 0) {
                    ForEach(1...5, id: \.self) { rating in
                        icon("\(rating) star\(rating == 1 ? "" : "s")", session.rating >= rating ? "StarFilled" : "Star", selected: session.rating >= rating, width: 30) {
                            Task { await session.setRating(session.rating == rating ? 0 : rating) }
                        }
                    }
                    icon("Unflagged", "Circle", selected: session.flag == "none", width: 32) { Task { await session.setFlag("none") } }
                    icon("Pick", "FlagPick", selected: session.flag == "pick", width: 32) { Task { await session.setFlag("pick") } }
                    icon("Reject", "FlagReject", selected: session.flag == "reject", width: 32) { Task { await session.setFlag("reject") } }
                }
                .padding(.horizontal, 6).background(.black.opacity(0.2), in: .capsule)
                Button(session.hasClipboard ? "Paste Edit Settings" : "Copy Edit Settings") { Task { await session.copyOrPaste() } }
                    .font(.subheadline).padding(.horizontal, 12).frame(height: 36)
                    .background(.black.opacity(0.2), in: .capsule)
                    .contextMenu { Button("Copy Edit Settings") { Task { await session.copyOrPaste(copyOnly: true) } } }
                    .disabled(session.groups.isEmpty)
                    .accessibilityIdentifier("photo-panel-copy-settings")
                copySettingsMenu
            }
            .padding(.horizontal, 10)
        }
        .scrollIndicators(.hidden).frame(height: 52)
        .background(.bar)
        .disabled(locked || session.busy || !session.model.isPhotoOpen)
        .accessibilityIdentifier("photo-panel-controls")
        .task(id: session.model.openPhoto) { await session.load() }
        .alert("Photo panel", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
        .accessibilityValue(session.status)
    }
    private func icon(_ title: String, _ name: String, selected: Bool = false, width: CGFloat = 40, action: @escaping () -> Void) -> some View {
        Button(title, lightCraftIcon: "LightCraft-\(name)", action: action)
            .labelStyle(.iconOnly).buttonStyle(.plain).frame(width: width, height: 40)
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
            .background(selected ? Color.primary.opacity(0.1) : .clear, in: .rect(cornerRadius: 8))
            .accessibilityAddTraits(selected ? .isSelected : [])
            .help(title)
    }
    private var sortMenu: some View {
        Menu {
            Section("Sort by") {
                ForEach([("Capture Date", "captureDate"), ("Import Date", "importDate"), ("Modified Date", "editDate"), ("File Name", "fileName"), ("Rating", "rating"), ("File Size", "fileSize"), ("Random", "random")], id: \.1) { title, key in
                    Button { Task { await session.sort(key) } } label: { selection(title, session.sortKey == key) }
                }
                if session.sortKey == "random" { Button("Reshuffle") { Task { await session.shuffle() } } }
            }
            Section {
                Button { Task { await session.sort(ascending: true) } } label: { selection("Ascending", session.ascending) }
                Button { Task { await session.sort(ascending: false) } } label: { selection("Descending", !session.ascending) }
            }.disabled(session.sortKey == "random")
            Section("Group by date") {
                ForEach([("Automatic", "auto"), ("Day", "day"), ("Month", "month"), ("Year", "year"), ("None", "none")], id: \.1) { title, group in
                    Button { Task { await session.sort(group: group) } } label: { selection(title, session.groupBy == group) }
                }
            }
        } label: { Label("Sort", lightCraftIcon: "LightCraft-Sort").labelStyle(.iconOnly).frame(width: 40, height: 40) }
        .help("Sort").accessibilityIdentifier("photo-panel-sort")
    }
    private var copySettingsMenu: some View {
        Menu {
            Button("Select All") { session.groups = Set(NativeSettingsGroup.allCases) }
            Button("Select None") { session.groups = [] }
            Button("Default Groups") { session.groups = NativeSettingsGroup.defaults }
            Divider()
            ForEach(NativeSettingsGroup.allCases) { group in
                Toggle(group.title, isOn: Binding(get: { session.groups.contains(group) }, set: { enabled in
                    if enabled { session.groups.insert(group) } else { session.groups.remove(group) }
                }))
            }
            Divider()
            Button("Copy Edit Settings") { Task { await session.copyOrPaste(copyOnly: true) } }.disabled(session.groups.isEmpty)
        } label: { Label("Copy Settings…", lightCraftIcon: "LightCraft-Gear").labelStyle(.iconOnly).frame(width: 40, height: 40) }
        .help("Copy Settings…").accessibilityIdentifier("photo-panel-copy-options")
    }
    @ViewBuilder private func selection(_ title: String, _ selected: Bool) -> some View {
        if selected { Label(title, lightCraftIcon: "LightCraft-Check") } else { Text(title) }
    }
}

/// PhotoPanelGallery provides edited previews for grids, side-by-side comparison and survey.
struct PhotoPanelGallery<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PhotoPanelSession<Engine, Importer>
    let open: (UInt64) -> Void
    private var selectionMode: Bool { session.mode == .compare || session.mode == .survey }
    var body: some View {
        VStack(spacing: 8) {
            if selectionMode {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(session.photos) { photo in
                            Button { session.toggleSelection(photo.id) } label: {
                                Label(photo.name, lightCraftIcon: session.selected.contains(photo.id) ? "LightCraft-Check" : "LightCraft-Circle")
                            }.buttonStyle(.bordered)
                        }
                    }.padding(8)
                }
                if session.selected.isEmpty { Text("Select photos to \(session.mode == .compare ? "compare" : "survey").").foregroundStyle(.secondary) }
            }
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        Section {
                            ForEach(section.photos) { photo in
                                PhotoPanelTile(session: session, photo: photo, large: selectionMode, square: session.mode == .squareGrid) { open(photo.id) }
                            }
                        } header: {
                            if !section.title.isEmpty { Text(section.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading) }
                        }
                    }
                }.padding(12)
                if session.photos.count < session.total && session.photos.count < 1000 {
                    Button("Load More Photos") { Task { await session.loadMore() } }.disabled(session.busy)
                }
            }
        }
        .overlay { if session.busy { ProgressView("Loading photos…") } }
        .background(EditorSurround.color)
        .accessibilityIdentifier("photo-panel-gallery")
    }
    private var shown: [PhotoMergeSession<Engine, Importer>.Photo] {
        if selectionMode {
            let ids = session.mode == .compare ? Array(session.selected.prefix(2)) : session.selected
            return ids.compactMap { id in session.photos.first { $0.id == id } }
        }
        return session.photos
    }
    private struct PhotoSection {
        let title: String
        var photos: [PhotoMergeSession<Engine, Importer>.Photo]
    }
    private var sections: [PhotoSection] {
        guard !selectionMode, session.sortKey == "captureDate", session.groupBy != "none" else {
            return [PhotoSection(title: "", photos: shown)]
        }
        var sections: [PhotoSection] = []
        let length = session.groupBy == "year" ? 4 : (session.groupBy == "month" ? 7 : 10)
        for photo in shown {
            let title = photo.captured.map { String($0.prefix(length)) } ?? "Unknown Date"
            if let last = sections.indices.last, sections[last].title == title { sections[last].photos.append(photo) }
            else { sections.append(PhotoSection(title: title, photos: [photo])) }
        }
        return sections
    }
    private var columns: [GridItem] {
        if session.mode == .compare { return [GridItem(.flexible()), GridItem(.flexible())] }
        if session.mode == .survey { return [GridItem(.adaptive(minimum: 260))] }
        return [GridItem(.adaptive(minimum: 160, maximum: 260))]
    }
}

private struct PhotoPanelTile<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    let session: PhotoPanelSession<Engine, Importer>
    let photo: PhotoMergeSession<Engine, Importer>.Photo
    let large: Bool
    let square: Bool
    let open: () -> Void
    @State private var image: UIImage?
    @State private var error: String?
    var body: some View {
        Button(action: open) {
            VStack(spacing: 6) {
                Group {
                    if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: .fit) }
                    else if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    else { ProgressView() }
                }
                .frame(maxWidth: .infinity)
                .frame(height: large ? 360 : (square ? 160 : 120))
                .background(.black.opacity(0.2))
                Text(photo.name).font(.caption).lineLimit(2)
            }.padding(6)
        }
        .buttonStyle(.plain)
        .help("Open \(photo.name)")
        .task(id: photo.id) {
            do { image = try await session.thumbnail(photo.id, large: large) }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
