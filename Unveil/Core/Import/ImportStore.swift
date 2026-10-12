//
//  ImportStore.swift
//  Unveil
//

import Foundation
import os
import Synchronization

/// ImportStore removes the copies in `Application Support/Imports` that the catalog no longer uses.
///
/// Nothing else ever deletes a copy: a reopened file whose bytes already live in the library is
/// relinked to its new copy, and the old one stays behind. The sweep keeps a copy whose file name
/// the catalog references (wherever the catalog thinks the folder is: see ImportCatalogReading),
/// the one of the photo open now, and any younger than `gracePeriod` (an open in flight has the
/// file on disk before the catalog knows it). It touches only regular files directly inside the
/// folder: a symlink or a subfolder is left alone, and nothing is followed.
///
/// It deletes nothing when it is not sure. A catalog that cannot be read, or answers only in part,
/// is unknown, not empty. An empty catalog is also skipped: it is more likely a library the app
/// did not mean to open than a user who removed every photo, and the cost is only some space.
///
/// Each candidate is checked again right before its delete, under PhotoImporter's reuse lock. A
/// copy can become referenced only through an open, and an open that reuses a copy refreshes its
/// date under that same lock first, so a recent date is the sign that the copy is wanted again.
nonisolated struct ImportStore<Catalog: ImportCatalogReading>: Sendable {

    let importsDirectory: URL
    let catalog         : Catalog
    let gracePeriod     : TimeInterval

    // A computed logger: a generic type cannot hold a static stored property.
    private static var logger: Logger {
        Logger(subsystem: "com.eliorodr2104.unveil", category: "ImportStore")
    }

    init(
        catalog         : Catalog,
        importsDirectory: URL          = PhotoImporter.defaultDirectory,
        gracePeriod     : TimeInterval = 600
    ) {
        self.catalog          = catalog
        self.importsDirectory = importsDirectory
        self.gracePeriod      = gracePeriod
    }

    /// sweep deletes the orphans off the main actor and reports what it freed. `openCopy` is the
    /// file of the photo shown now.
    @concurrent
    func sweep(keeping openCopy: URL?, now: Date = .now) async -> ImportSweepReport {
        var keptNames: Set<String>

        do {
            keptNames = try await catalog.referencedFileNames()
        } catch {
            let reason = error.message
            Self.logger.error("Import sweep skipped, catalog unknown: \(reason, privacy: .public)")
            return .nothing
        }

        guard !keptNames.isEmpty else {
            Self.logger.info("Import sweep skipped: the catalog is empty")
            return .nothing
        }

        if let openCopy {
            keptNames.insert(openCopy.lastPathComponent)
        }

        let entries: [URL]
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at                         : importsDirectory,
                includingPropertiesForKeys : nil
            )
        } catch {
            return .nothing
        }

        var removed = 0
        var freed   = Int64(0)

        for entry in entries where !keptNames.contains(entry.lastPathComponent) {
            if let bytes = removeIfUnused(entry, now: now) {
                removed += 1
                freed   += bytes
            }
        }

        Self.logger.info("Import sweep removed \(removed) copies, \(freed) bytes")
        return ImportSweepReport(removedCount: removed, freedBytes: freed)
    }

    /// removeIfUnused deletes `entry` if, read now under the reuse lock, it is a regular file (not
    /// a symlink: attributesOfItem does not follow one) older than the grace period. It returns
    /// the bytes freed, or nil when the file stays.
    private func removeIfUnused(_ entry: URL, now: Date) -> Int64? {
        PhotoImporter.reuseLock.withLock { _ -> Int64? in
            let path = entry.path(percentEncoded: false)

            guard
                let attributes = try? FileManager.default.attributesOfItem(atPath: path),
                attributes[.type] as? FileAttributeType == .typeRegular,
                let modified = attributes[.modificationDate] as? Date,
                now.timeIntervalSince(modified) > gracePeriod
            else { return nil }

            do {
                try FileManager.default.removeItem(at: entry)
                return (attributes[.size] as? NSNumber)?.int64Value ?? 0
            } catch {
                let reason = error.localizedDescription
                Self.logger.error("Deleting an orphan copy failed: \(reason, privacy: .public)")
                return nil
            }
        }
    }
}
