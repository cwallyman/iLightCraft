//
//  TestDataCleaner.swift
//  iLightCraft
//

import Foundation

/// TestDataCleaner deletes the folders the diagnostics generate in Documents (`golden` and
/// `measurements`) and nothing else: Documents also holds the user's `raw` folder, which stays.
/// A path that is a symlink, or not a folder, is skipped rather than followed.
nonisolated struct TestDataCleaner: Sendable {

    let directories: [URL]

    init(
        directories: [URL] = [
            URL.documentsDirectory.appending(path: "golden", directoryHint: .isDirectory),
            URL.documentsDirectory.appending(path: "measurements", directoryHint: .isDirectory),
        ]
    ) {
        self.directories = directories
    }

    /// removeAll deletes each folder and returns the bytes of the files inside them.
    @concurrent
    func removeAll() async -> Int64 {
        let fileManager = FileManager.default
        var freed       = Int64(0)

        let folderKeys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]

        for directory in directories {
            let values = try? directory.resourceValues(forKeys: folderKeys)
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }

            let files = fileManager.enumerator(
                at                         : directory,
                includingPropertiesForKeys : [.fileSizeKey]
            )
            while let file = files?.nextObject() as? URL {
                freed += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }

            try? fileManager.removeItem(at: directory)
        }

        return freed
    }
}
