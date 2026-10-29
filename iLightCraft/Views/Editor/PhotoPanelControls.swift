//
//  PhotoPanelControls.swift
//  iLightCraft
//

import SwiftUI

/// PhotoPanelControls follows LightCraft's bottom bar: views, sort, rating/flags and copy settings.
struct PhotoPanelControls<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @Bindable var session: PhotoPanelSession<Engine, Importer>
    let locked: Bool
    var floating = false
    var onHold: ((Bool) -> Void)? = nil
    var onFit: (() -> Void)? = nil
    var clipping: Binding<ClippingOverlay>? = nil
    var openPhoto: ((UInt64) -> Void)? = nil
    let chooseMode: (PhotoPanelMode) -> Void
    @State private var barWidth: CGFloat = 0
    var body: some View {
        Group { if floating { floatingBar } else { classicBar } }
        .disabled(locked || session.busy || !session.model.isPhotoOpen)
        .accessibilityIdentifier("photo-panel-controls")
        .task(id: session.model.openPhoto) { await session.load() }
        .alert("Photo panel", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
        .accessibilityValue(session.status)
    }

    /// floatingBar is the iPad's glass capsule over the photo, with a filmstrip at its leading edge
    /// when there is room. Rating, flags, sort and copy settings stay one tap away in its menus.
    private var floatingBar: some View {
        ZStack {
            if let openPhoto, barWidth >= 760 {
                HStack { PhotoFilmstrip(session: session, open: openPhoto); Spacer() }
            }
            HStack(spacing: 4) {
                let comparing = session.mode == .beforeAfter
                glassIcon(PhotoPanelMode.beforeAfter.title, lightCraft: PhotoPanelMode.beforeAfter.icon, selected: comparing) {
                    chooseMode(comparing ? .detail : .beforeAfter)
                }
                if let onHold {
                    Text("Hold for Original").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).frame(height: 40)
                        .background(Color.white.opacity(0.1), in: .capsule)
                        .contentShape(.capsule)
                        .onLongPressGesture(minimumDuration: 0, maximumDistance: 60, perform: {}, onPressingChanged: onHold)
                        .accessibilityAddTraits(.isButton)
                        .accessibilityIdentifier("hold-for-original")
                }
                if let onFit {
                    glassIcon("Zoom to Fit", system: "viewfinder", action: onFit)
                }
                if let clipping {
                    let on = !clipping.wrappedValue.isEmpty
                    glassIcon(on ? "Hide Clipping" : "Show Clipping", system: "exclamationmark.triangle", tint: on ? .red : Color(red: 1, green: 0.42, blue: 0.4), selected: on) {
                        clipping.wrappedValue = on ? [] : [.shadows, .highlights]
                    }
                }
                Rectangle().fill(Color.white.opacity(0.15)).frame(width: 1, height: 24).padding(.horizontal, 4)
                ratingMenu
                Menu {
                    Button(session.hasClipboard ? "Paste Edit Settings" : "Copy Edit Settings") { Task { await session.copyOrPaste() } }
                        .disabled(session.groups.isEmpty)
                    Button("Copy Edit Settings") { Task { await session.copyOrPaste(copyOnly: true) } }
                        .disabled(session.groups.isEmpty)
                    copySettingsMenu
                    sortMenu
                    Section("View") {
                        ForEach([PhotoPanelMode.detail, .photoGrid, .squareGrid, .compare, .survey]) { mode in
                            Button(mode.title, lightCraftIcon: "LightCraft-\(mode.icon)") { chooseMode(mode) }
                        }
                    }
                } label: {
                    Image(lightCraftIcon: "LightCraft-More").resizable().scaledToFit().frame(width: 20, height: 20)
                        .frame(width: 40, height: 40).contentShape(.circle)
                }
                .accessibilityLabel("Photo Options").accessibilityIdentifier("photo-panel-copy-settings")
            }
            .padding(5)
            .lightCraftFloatingGlass(.capsule)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { barWidth = $0 }
    }

    private var ratingMenu: some View {
        Menu {
            Section("Rating") {
                ForEach((0...5).reversed(), id: \.self) { rating in
                    Button { Task { await session.setRating(rating) } } label: {
                        selection(rating == 0 ? "No Rating" : String(repeating: "★", count: rating), session.rating == rating)
                    }
                }
            }
            Section("Flag") {
                Button { Task { await session.setFlag("pick") } } label: { selection("Pick", session.flag == "pick") }
                Button { Task { await session.setFlag("reject") } } label: { selection("Reject", session.flag == "reject") }
                Button { Task { await session.setFlag("none") } } label: { selection("Unflagged", session.flag == "none") }
            }
        } label: {
            HStack(spacing: 4) {
                Image(lightCraftIcon: session.rating > 0 ? "LightCraft-StarFilled" : "LightCraft-Star").resizable().scaledToFit().frame(width: 18, height: 18)
                if session.rating > 0 { Text("\(session.rating)").font(.subheadline.weight(.semibold)).monospacedDigit() }
                if session.flag != "none" {
                    Image(lightCraftIcon: session.flag == "pick" ? "LightCraft-FlagPick" : "LightCraft-FlagReject").resizable().scaledToFit().frame(width: 16, height: 16)
                }
            }
            .foregroundStyle(session.rating > 0 || session.flag != "none" ? LightCraftPanelStyle.highlight : .white)
            .padding(.horizontal, 10).frame(minWidth: 40, minHeight: 40).contentShape(.capsule)
        }
        .accessibilityLabel("Rating and Flag").accessibilityIdentifier("photo-panel-rating")
    }

    private func glassIcon(_ title: String, lightCraft: String? = nil, system: String? = nil, tint: Color = .white, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let lightCraft { Image(lightCraftIcon: "LightCraft-\(lightCraft)").resizable().scaledToFit().frame(width: 20, height: 20) }
                else if let system { Image(systemName: system).font(.system(size: 17, weight: .medium)) }
            }
            .foregroundStyle(tint)
            .frame(width: 40, height: 40)
            .background(selected ? LightCraftPanelStyle.highlight.opacity(0.3) : .clear, in: .circle)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title).help(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var classicBar: some View {
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

/// PhotoFilmstrip shows the open photo's neighbours as round thumbnails; tapping one opens it.
struct PhotoFilmstrip<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    let session: PhotoPanelSession<Engine, Importer>
    let open: (UInt64) -> Void
    private var nearby: [PhotoMergeSession<Engine, Importer>.Photo] {
        let current = session.photos.firstIndex { $0.id == session.model.openPhoto?.rawValue } ?? 0
        let start = max(0, min(current - 2, session.photos.count - 5))
        return Array(session.photos.dropFirst(start).prefix(5))
    }
    var body: some View {
        HStack(spacing: 6) {
            ForEach(nearby) { photo in
                PhotoFilmstripTile(session: session, photo: photo, selected: photo.id == session.model.openPhoto?.rawValue) { open(photo.id) }
            }
        }
        .padding(5)
        .lightCraftFloatingGlass(.capsule)
        .opacity(session.photos.isEmpty ? 0 : 1)
        .task(id: session.model.openPhoto) {
            // The panel's own load runs first and holds the busy flag.
            while session.busy { try? await Task.sleep(for: .milliseconds(150)) }
            if session.photos.isEmpty { await session.reloadPhotos() }
        }
        .accessibilityIdentifier("photo-filmstrip")
    }
}

private struct PhotoFilmstripTile<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    let session: PhotoPanelSession<Engine, Importer>
    let photo: PhotoMergeSession<Engine, Importer>.Photo
    let selected: Bool
    let open: () -> Void
    @State private var image: UIImage?
    var body: some View {
        Button(action: open) {
            Group {
                if let image { Image(uiImage: image).resizable().scaledToFill() } else { Color.white.opacity(0.08) }
            }
            .frame(width: 40, height: 40).clipShape(.circle)
            .overlay(Circle().strokeBorder(selected ? LightCraftPanelStyle.highlight : .clear, lineWidth: 2))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open \(photo.name)")
        .task(id: photo.id) { image = try? await session.thumbnail(photo.id) }
    }
}
