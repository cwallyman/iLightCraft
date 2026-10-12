//
//  TemporaryEngineLibrary.swift
//  UnveilTests
//

import Foundation

/// TemporaryEngineLibrary names a new engine library folder in the temporary area for one test.
///
/// A test cannot remove its own folder: EngineManager frees the session asynchronously in deinit,
/// so the library may still be open when the test ends. Instead the first call of a test run
/// removes the `engine-*` folders older than an hour, which no session of this run can hold.
nonisolated enum TemporaryEngineLibrary {

    static func make() -> URL {
        _ = staleLibrariesRemoved
        return FileManager.default.temporaryDirectory.appending(path: "engine-\(UUID())")
    }

    // A static let runs once per process, at the first `make()`: once per test run.
    private static let staleLibrariesRemoved: Void = {
        let fileManager = FileManager.default
        let cutoff      = Date.now.addingTimeInterval(-3600)
        let entries     = (try? fileManager.contentsOfDirectory(
            at                         : fileManager.temporaryDirectory,
            includingPropertiesForKeys : [.contentModificationDateKey]
        )) ?? []

        for entry in entries where entry.lastPathComponent.hasPrefix("engine-") {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
            if let modified, modified < cutoff {
                try? fileManager.removeItem(at: entry)
            }
        }
    }()
}
