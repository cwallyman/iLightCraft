import Foundation

/// Recovery is staged in a new app-owned library and activated only at the next launch.
/// Both engine and imports switch together; the old library is never replaced.
nonisolated enum NativeLibraryLocation {
    static let activeKey = "native.activeRecoveredLibrary"
    static let pendingKey = "native.pendingRecoveredLibrary"
    static var root: URL {
        if let id = UserDefaults.standard.string(forKey: activeKey), UUID(uuidString: id) != nil {
            return recoveredRoot(id)
        }
        return URL.applicationSupportDirectory
    }
    static var engine: URL { root.appending(path: "Engine", directoryHint: .isDirectory) }
    static func recoveredRoot(_ id: String) -> URL {
        URL.applicationSupportDirectory.appending(path: "RecoveredLibraries", directoryHint: .isDirectory).appending(path: id, directoryHint: .isDirectory)
    }
    static func activatePending() -> Bool {
        guard let id = UserDefaults.standard.string(forKey: pendingKey), UUID(uuidString: id) != nil else { return false }
        let candidate = recoveredRoot(id).appending(path: "Engine/catalog.snap")
        guard FileManager.default.fileExists(atPath: candidate.path) else { return false }
        UserDefaults.standard.set(id, forKey: activeKey)
        UserDefaults.standard.removeObject(forKey: pendingKey)
        return true
    }
}
