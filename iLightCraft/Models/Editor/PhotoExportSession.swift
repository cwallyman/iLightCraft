//
//  PhotoExportSession.swift
//  iLightCraft
//

import Foundation
import Observation

/// PhotoExportSession writes one photo at a time to its own temporary folder for the system share sheet.
@Observable
@MainActor
final class PhotoExportSession<Engine: EngineDriving & EngineDiagnosing, Importer: PhotoImporting> {

    var options = PhotoExportOptions()
    var selected: Set<UInt64> = []
    private(set) var photos: [Photo] = []
    private(set) var total = 0
    private(set) var isWorking = false
    private(set) var completed = 0
    private(set) var requested = 0
    private(set) var files: [URL] = []
    var error: String?
    var stopRequested = false
    let supportsHDR: Bool

    private let model: EditorViewModel<Engine, Importer>
    private var directory: URL?

    nonisolated struct Photo: Decodable, Identifiable, Sendable {

        let id: UInt64
        let fileName: String
        let title: String?
        let copyName: String?

        var name: String {
            let suffix = copyName.map { $0.isEmpty ? "" : " (\($0))" } ?? ""
            if let title, !title.isEmpty { return title + suffix }
            let stem = URL(filePath: fileName).deletingPathExtension().lastPathComponent
            let prefix = stem.prefix(64)
            if prefix.count == 64, prefix.allSatisfy({ $0.isHexDigit }), stem.dropFirst(64).first == "-" {
                return String(stem.dropFirst(65)) + suffix
            }
            return stem + suffix
        }
    }

    nonisolated private struct Query: Encodable, Sendable {

        let filter: [String: String] = [:]
        let offset: Int
        let limit = 200
    }

    nonisolated private struct Page: Decodable {

        let total: Int
        let photos: [Photo]
    }

    nonisolated private struct Request: Encodable, Sendable {

        let id: UInt64
        let path: String
        let options: PhotoExportOptions

        enum CodingKeys: String, CodingKey { case id, path }

        func encode(to encoder: Encoder) throws {
            try options.encode(to: encoder)
            var fields = encoder.container(keyedBy: CodingKeys.self)
            try fields.encode(id, forKey: .id)
            try fields.encode(path, forKey: .path)
        }
    }

    init(model: EditorViewModel<Engine, Importer>) {
        self.model = model
        supportsHDR = model.hdrEnabled
        if let photo = model.openPhoto { selected = [photo.rawValue] }
    }

    func loadMore() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let json = try await model.photoCommand("catalog.query", params: Query(offset: photos.count))
            let page = try JSONDecoder().decode(Page.self, from: Data(json.utf8))
            total = page.total
            photos.append(contentsOf: page.photos)
        } catch {
            self.error = (error as? EngineError)?.message ?? error.localizedDescription
        }
    }

    func export() async {
        guard !isWorking, !selected.isEmpty else { return }
        isWorking = true
        stopRequested = false
        completed = 0
        files = []
        error = nil
        let ids = selected.sorted()
        requested = ids.count
        let options = options
        defer { isWorking = false }

        do {
            let folder = URL.temporaryDirectory.appending(path: "iLightCraftExport-\(UUID())", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            directory = folder
            for (index, id) in ids.enumerated() {
                if stopRequested { break }
                let name = photos.first { $0.id == id }?.name ?? model.photoTitle
                let safeName = String(name.map { "/\\:\0".contains($0) ? "_" : $0 }.prefix(120))
                let base = safeName.isEmpty ? "Photo" : safeName
                let url = folder.appending(path: "\(base)-\(index + 1).\(options.fileExtension)")
                var encodedOptions = options
                let hdr = options.hdr || options.format == "heic"
                let intermediate = options.format == "heic" ? folder.appending(path: "hdr-\(id).tiff") : url
                if hdr {
                    encodedOptions.format = "tiff"
                    encodedOptions.bitDepth = 32
                }
                _ = try await model.photoCommand(hdr ? "ilightcraft.hdrExport" : "ilightcraft.export", params: Request(
                    id: id, path: intermediate.path(percentEncoded: false), options: encodedOptions
                ))
                if options.format == "heic" {
                    try await Task.detached(priority: .userInitiated) {
                        try NativeImagePipeline.encodeHDR(source: intermediate, destination: url)
                    }.value
                    try FileManager.default.removeItem(at: intermediate)
                }
                files.append(url)
                completed += 1
            }
        } catch {
            self.error = (error as? EngineError)?.message ?? error.localizedDescription
        }
    }

    func cleanUp() {
        guard !isWorking, let directory else { return }
        do {
            try FileManager.default.removeItem(at: directory)
            self.directory = nil
            files = []
        } catch {
            self.error = error.localizedDescription
        }
    }
}
