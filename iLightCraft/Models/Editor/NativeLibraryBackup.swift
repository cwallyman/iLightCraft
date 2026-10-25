import CryptoKit
import Foundation

nonisolated enum NativeLibraryBackup {
    struct Manifest: Codable, Sendable {
        let format: String
        let version: Int
        let originalRoot: String
        let created: String
        let relocatedSources: [String: String]
        let files: [File]
        struct File: Codable, Sendable { let path: String; let bytes: UInt64; let sha256: String }
    }
    enum BackupError: LocalizedError {
        case invalid(String)
        var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
    }
    static func safeRelative(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"), path.utf8.count <= 4096 else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
    static func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 4 * 1024 * 1024), !bytes.isEmpty {
            try Task.checkCancellation(); hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func regularFile(_ url: URL, within root: URL) throws -> UInt64 {
        guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else { throw BackupError.invalid("Backup contains an unsafe path") }
        let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard info.isRegularFile == true, info.isSymbolicLink != true, let bytes = info.fileSize, bytes >= 0 else { throw BackupError.invalid("Backup contains a non-regular file") }
        return UInt64(bytes)
    }
    static func create(root: URL, destination: URL, progress: @Sendable (Double) -> Void) throws -> URL {
        let fm = FileManager.default
        let destinationPath = destination.resolvingSymlinksInPath().path
        let libraryPath = root.resolvingSymlinksInPath().path
        guard destinationPath != libraryPath, !destinationPath.hasPrefix(libraryPath + "/") else { throw BackupError.invalid("Choose a backup folder outside the active library") }
        let package = destination.appending(path: "iLightCraft-Backup-\(UUID().uuidString).lightcraftbackup", directoryHint: .isDirectory)
        guard !fm.fileExists(atPath: package.path) else { throw BackupError.invalid("Backup destination already exists") }
        try fm.createDirectory(at: package, withIntermediateDirectories: false)
        var finished = false
        defer { if !finished { try? fm.removeItem(at: package) } }
        var sources: [(URL, String)] = []
        for directory in ["Engine", "Imports"] {
            let base = root.appending(path: directory, directoryHint: .isDirectory)
            guard fm.fileExists(atPath: base.path) else { continue }
            var enumerationError: Error?
            guard let entries = fm.enumerator(at: base, includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey], errorHandler: { _, error in enumerationError = error; return false }) else { throw BackupError.invalid("Cannot enumerate library files") }
            for case let file as URL in entries {
                try Task.checkCancellation()
                let values = try file.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw BackupError.invalid("Library contains symbolic links; backup was not created") }
                if values.isDirectory == true {
                    if ["cache", "thumbs", "thumbnails", "previews"].contains(file.lastPathComponent.lowercased()) { entries.skipDescendants() }
                    continue
                }
                let name = file.lastPathComponent
                if name.hasSuffix(".lock") || ["catalog.log", "photos-links.json", "catalog.lock"].contains(name) { continue }
                let prefix = root.standardizedFileURL.path + "/"
                guard file.standardizedFileURL.path.hasPrefix(prefix) else { throw BackupError.invalid("Invalid library path") }
                let relative = String(file.standardizedFileURL.path.dropFirst(prefix.count))
                guard safeRelative(relative) else { throw BackupError.invalid("Invalid library filename") }
                sources.append((file, relative))
                guard sources.count <= 100000 else { throw BackupError.invalid("Backup supports up to 100,000 files") }
            }
            if let enumerationError { throw enumerationError }
        }
        let snapshotURL = root.appending(path: "Engine/catalog.snap")
        let size = try snapshotURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0, size <= 64 * 1024 * 1024 else { throw BackupError.invalid("Library snapshot is missing or exceeds 64 MiB") }
        let snapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: snapshotURL)) as? [String: Any]
        guard let catalog = snapshot?["catalog"] as? [String: Any], let photos = catalog["photos"] as? [String: Any] else { throw BackupError.invalid("Cannot read library snapshot") }
        var relocated: [String: String] = [:]
        let managed = Set(sources.map { $0.0.standardizedFileURL.path })
        for value in photos.values {
            guard let photo = value as? [String: Any], let source = photo["source"] as? [String: Any], source["type"] as? String == "file", let path = source["path"] as? String else { continue }
            let url = URL(filePath: path).standardizedFileURL
            if !managed.contains(url.path) && relocated[url.path] == nil {
                let info = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard info.isRegularFile == true, info.isSymbolicLink != true else { throw BackupError.invalid("An imported source is missing or is a symbolic link") }
                let relative = "ExternalMedia/\(UUID().uuidString)-\(url.lastPathComponent)"
                guard safeRelative(relative) else { throw BackupError.invalid("An imported source filename is unsafe") }
                relocated[url.path] = relative; sources.append((url, relative))
            }
        }
        guard sources.contains(where: { $0.1 == "Engine/catalog.snap" }), sources.count <= 100000 else { throw BackupError.invalid("Backup file count is invalid") }
        var files: [Manifest.File] = []
        for (index, source) in sources.enumerated() {
            try Task.checkCancellation()
            let (file, relative) = source
            let target = package.appending(path: relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = try hash(file)
            try fm.copyItem(at: file, to: target)
            let bytes = try regularFile(target, within: package)
            guard try hash(target) == before else { throw BackupError.invalid("A source changed during backup; retry after editing stops") }
            files.append(.init(path: relative, bytes: bytes, sha256: before))
            if index % 20 == 0 { progress(Double(index + 1) / Double(max(1, sources.count))) }
        }
        let manifest = Manifest(format: "iLightCraft-library-backup", version: 1, originalRoot: root.standardizedFileURL.path,
                                created: ISO8601DateFormatter().string(from: Date()), relocatedSources: relocated, files: files)
        let data = try JSONEncoder().encode(manifest)
        guard data.count <= 32 * 1024 * 1024 else { throw BackupError.invalid("Backup manifest exceeds 32 MiB") }
        try data.write(to: package.appending(path: "manifest.json"), options: .withoutOverwriting)
        progress(1); finished = true; return package
    }
    static func restore(package: URL, progress: @Sendable (Double) -> Void) throws -> String {
        let fm = FileManager.default
        let manifestURL = package.appending(path: "manifest.json")
        let manifestSize = try regularFile(manifestURL, within: package)
        guard manifestSize > 0, manifestSize <= 32 * 1024 * 1024 else { throw BackupError.invalid("Invalid backup manifest size") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.format == "iLightCraft-library-backup", manifest.version == 1, !manifest.files.isEmpty, manifest.files.count <= 100000,
              manifest.originalRoot.hasPrefix("/"), manifest.files.contains(where: { $0.path == "Engine/catalog.snap" }) else { throw BackupError.invalid("Unsupported or incomplete library backup") }
        let id = UUID().uuidString
        let recovered = NativeLibraryLocation.recoveredRoot(id)
        guard !fm.fileExists(atPath: recovered.path) else { throw BackupError.invalid("Recovery destination already exists") }
        try fm.createDirectory(at: recovered, withIntermediateDirectories: true)
        var finished = false
        defer { if !finished { try? fm.removeItem(at: recovered) } }
        var seen: Set<String> = []
        for (index, entry) in manifest.files.enumerated() {
            try Task.checkCancellation()
            guard safeRelative(entry.path), seen.insert(entry.path).inserted,
                  ["Engine", "Imports", "ExternalMedia"].contains(String(entry.path.split(separator: "/").first ?? "")),
                  entry.sha256.count == 64, entry.sha256.allSatisfy(\.isHexDigit),
                  !entry.path.hasSuffix(".lock"), !entry.path.hasSuffix("photos-links.json"), !entry.path.hasSuffix("catalog.log") else { throw BackupError.invalid("Backup contains an unsafe or duplicate entry") }
            let source = package.appending(path: entry.path)
            guard try regularFile(source, within: package) == entry.bytes, try hash(source) == entry.sha256 else { throw BackupError.invalid("Backup checksum failed; the current library is unchanged") }
            let target = recovered.appending(path: entry.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
            guard try hash(target) == entry.sha256 else { throw BackupError.invalid("Recovery copy verification failed") }
            if index % 20 == 0 { progress(Double(index + 1) / Double(max(1, manifest.files.count))) }
        }
        for path in ["Engine/catalog.snap", "Engine/prefs.json"] {
            let file = recovered.appending(path: path)
            guard fm.fileExists(atPath: file.path) else { continue }
            let bytes = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard bytes <= 64 * 1024 * 1024 else { throw BackupError.invalid("Recovered catalog or preferences exceed 64 MiB") }
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: file))
            let migrated = try rewrite(object, from: manifest.originalRoot, to: recovered.path, external: manifest.relocatedSources, depth: 0)
            try JSONSerialization.data(withJSONObject: migrated, options: .sortedKeys).write(to: file, options: .atomic)
        }
        let restoredSnapshot = try JSONSerialization.jsonObject(with: Data(contentsOf: recovered.appending(path: "Engine/catalog.snap"))) as? [String: Any]
        guard restoredSnapshot?["format"] as? String == "lightcraft-catalog", restoredSnapshot?["catalog"] is [String: Any] else { throw BackupError.invalid("Recovered catalog format is invalid") }
        guard let restoredCatalog = restoredSnapshot?["catalog"] as? [String: Any], let restoredPhotos = restoredCatalog["photos"] as? [String: Any] else { throw BackupError.invalid("Invalid recovered photo table") }
        for value in restoredPhotos.values {
            guard let photo = value as? [String: Any], let source = photo["source"] as? [String: Any], source["type"] as? String == "file", let path = source["path"] as? String else { continue }
            let prefix = recovered.standardizedFileURL.path + "/"
            let url = URL(filePath: path).standardizedFileURL
            guard url.path.hasPrefix(prefix), seen.contains(String(url.path.dropFirst(prefix.count))) else { throw BackupError.invalid("Recovered photo references media outside this backup") }
            _ = try regularFile(url, within: recovered)
        }
        progress(1); finished = true; return id
    }
    private static func rewrite(_ value: Any, from original: String, to recovered: String, external: [String: String], depth: Int) throws -> Any {
        guard depth < 64 else { throw BackupError.invalid("Backup JSON nesting is too deep") }
        if let value = value as? String {
            if let relative = external[value] {
                guard safeRelative(relative) else { throw BackupError.invalid("Unsafe relocated source") }
                return URL(filePath: recovered).appending(path: relative).path
            }
            if value.hasPrefix(original + "/") {
                let relative = String(value.dropFirst(original.count + 1))
                guard safeRelative(relative) else { throw BackupError.invalid("Unsafe catalog source path") }
                return URL(filePath: recovered).appending(path: relative).path
            }
            return value
        }
        if let values = value as? [Any] { return try values.map { try rewrite($0, from: original, to: recovered, external: external, depth: depth + 1) } }
        if let values = value as? [String: Any] {
            return try values.mapValues { try rewrite($0, from: original, to: recovered, external: external, depth: depth + 1) }
        }
        return value
    }
}
