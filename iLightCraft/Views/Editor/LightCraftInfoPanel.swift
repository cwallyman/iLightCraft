//
//  LightCraftInfoPanel.swift
//  iLightCraft
//

import SwiftUI
import Observation

/// LightCraftInfoSession exposes the same descriptive metadata fields as the desktop Info panel.
@Observable @MainActor
final class LightCraftInfoSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {
    let model: EditorViewModel<Engine, Importer>
    var values: [String: String] = [:]
    private(set) var capture: [(String, String)] = []
    private(set) var tags: [(String, String)] = []
    private(set) var busy = false
    var error: String?
    nonisolated static var fields: [(String, String, String)] {
        [("Title", "title", "title"), ("Caption", "caption", "caption"), ("Alt Text", "altText", "alt_text"),
         ("Extended Description", "extendedDescription", "extended_description"), ("Copyright", "copyright", "copyright"),
         ("Rights Usage Terms", "usageTerms", "usage_terms"), ("Copyright Info URL", "copyrightUrl", "copyright_url"),
         ("Creator", "creator", "creator"), ("Location", "location", "location"), ("City", "city", "city"),
         ("State / Province", "state", "state"), ("Country", "country", "country")]
    }
    init(model: EditorViewModel<Engine, Importer>) { self.model = model }
    func load() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await read() } catch { self.error = error.localizedDescription }
    }
    private func read() async throws {
        let json = try await model.photoCommand("photo.inspect", params: [String: String]())
        guard let photo = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let metadata = photo["meta"] as? [String: Any] else { throw EngineError.engine("Invalid photo metadata") }
        for (_, key, stored) in Self.fields { values[key] = metadata[stored] as? String ?? "" }
        values["copyrightStatus"] = metadata["copyright_status"] as? String ?? "unknown"
        var rows: [(String, String)] = []
        for (label, key) in [("Camera", "camera"), ("Lens", "lens"), ("ISO", "iso"), ("Aperture", "aperture"), ("Shutter", "shutter"), ("Focal Length", "focal_mm"), ("GPS", "gps")] {
            if let value = metadata[key], !(value is NSNull) { rows.append((label, String(describing: value))) }
        }
        for (label, key) in [("File Name", "file_name"), ("Captured", "captured")] {
            if let value = photo[key] as? String { rows.append((label, value)) }
        }
        if let source = photo["source"] as? [String: Any], let path = source["path"] as? String { rows.append(("File Path", path)) }
        if let width = photo["width"] as? Int, let height = photo["height"] as? Int { rows.append(("Dimensions", "\(width) × \(height)")) }
        capture = rows
    }
    func save(_ key: String) async {
        guard !busy, Self.fields.contains(where: { $0.1 == key }) || key == "copyrightStatus", let value = values[key], value.utf8.count <= 65_536, let photo = model.openPhoto else { return }
        busy = true; error = nil; defer { busy = false }
        do { _ = try await model.photoCommand("photo.setMeta", params: MetadataWrite(ids: [photo.rawValue], fields: [key: value])); try await read() }
        catch { self.error = error.localizedDescription }
    }
    nonisolated private struct MetadataWrite: Encodable, Sendable {
        let ids: [UInt64]
        let fields: [String: String]
        struct Key: CodingKey {
            let stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: Key.self)
            try values.encode(ids, forKey: Key(stringValue: "ids"))
            for (key, value) in fields { try values.encode(value, forKey: Key(stringValue: key)) }
        }
    }
    func saveMetadata() async {
        guard !busy, let photo = model.openPhoto else { return }
        let keys = Set(Self.fields.map { $0.1 } + ["copyrightStatus"])
        let fields = values.filter { keys.contains($0.key) }
        guard fields.values.allSatisfy({ $0.utf8.count <= 65_536 }) else { error = "A metadata field exceeds 64 KiB."; return }
        busy = true; error = nil; defer { busy = false }
        do {
            _ = try await model.photoCommand("photo.setMeta", params: MetadataWrite(ids: [photo.rawValue], fields: fields))
            try await read()
        } catch { self.error = error.localizedDescription }
    }
    func allMetadata() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let json = try await model.photoCommand("photo.allMetadata", params: [String: String]())
            guard let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { throw EngineError.engine("Invalid metadata response") }
            let rows = (value["exif"] as? [[String: Any]] ?? []) + (value["xmp"] as? [[String: Any]] ?? [])
            guard rows.count <= 20_000 else { throw EngineError.engine("Too many metadata tags to display") }
            tags = rows.map { (String(describing: $0["name"] ?? "Tag"), String(describing: $0["value"] ?? "")) }
        } catch { self.error = error.localizedDescription }
    }
}

struct LightCraftInfoPanel<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting>: View {
    @State private var session: LightCraftInfoSession<Engine, Importer>
    @Bindable var photoPanel: PhotoPanelSession<Engine, Importer>
    @Environment(\.editorToolClose) private var close
    init(model: EditorViewModel<Engine, Importer>, photoPanel: PhotoPanelSession<Engine, Importer>) {
        _session = State(initialValue: LightCraftInfoSession(model: model)); self.photoPanel = photoPanel
    }
    var body: some View {
        EditorToolPresentation(title: "Info", header: { EmptyView() }) {
            LightCraftMenuList {
                LightCraftMenuSection("Camera & File") {
                    ForEach(Array(session.capture.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1).textSelection(.enabled)
                    }
                }
                LightCraftMenuSection("Rating") {
                    Picker("Rating", selection: Binding(get: { photoPanel.rating }, set: { value in Task { await photoPanel.setRating(value) } })) {
                        Text("Unrated").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) stars").tag($0) }
                    }
                    Menu("Color Label") {
                        ForEach(["none", "red", "yellow", "green", "blue", "purple"], id: \.self) { label in
                            Button(label.capitalized) { Task { await setLabel(label) } }
                        }
                    }
                }
                LightCraftMenuSection("Description & Rights") {
                    ForEach(LightCraftInfoSession<Engine, Importer>.fields, id: \.1) { title, key, _ in
                        VStack(alignment: .leading) {
                            Text(title).font(.caption).foregroundStyle(.secondary)
                            TextField(title, text: Binding(get: { session.values[key] ?? "" }, set: { session.values[key] = $0 }), axis: .vertical)
                        }
                    }
                    Picker("Copyright Status", selection: Binding(get: { session.values["copyrightStatus"] ?? "unknown" }, set: { value in session.values["copyrightStatus"] = value; Task { await session.save("copyrightStatus") } })) {
                        Text("Unknown").tag("unknown"); Text("Copyrighted").tag("copyrighted"); Text("Public Domain").tag("publicDomain")
                    }
                }
                LightCraftMenuSection {
                    Button("Save Metadata") { Task { await session.saveMetadata() } }
                    Text("Metadata is saved in this library.").font(.caption).foregroundStyle(.secondary)
                }
                LightCraftMenuSection("All Metadata") {
                    Button("Show All Metadata") { Task { await session.allMetadata() } }
                    ForEach(Array(session.tags.enumerated()), id: \.offset) { _, row in
                        LabeledContent(row.0, value: row.1).font(.caption).textSelection(.enabled)
                    }
                }
                if session.busy { ProgressView() }
                if let error = session.error { Text(error).foregroundStyle(.red) }
            }.disabled(session.busy)
        }
        .task { await session.load(); await photoPanel.load() }
        .modifier(EditorToolBusyReporter(busy: session.busy || photoPanel.busy))
    }
    nonisolated private struct ColorLabelWrite: Encodable, Sendable { let label: String; let ids: [UInt64] }
    private func setLabel(_ label: String) async {
        guard let photo = session.model.openPhoto else { return }
        do { _ = try await session.model.photoCommand("photo.label", params: ColorLabelWrite(label: label, ids: [photo.rawValue])) }
        catch { session.error = error.localizedDescription }
    }
}
