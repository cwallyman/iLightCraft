//
//  PhotoImporterTests.swift
//  iLightCraftTests
//

import Foundation
import Testing
@testable import iLightCraft

/// A class, so `deinit` removes each test's folder: Swift Testing makes one instance per test.
final class PhotoImporterTests {

    let root = FileManager.default.temporaryDirectory.appending(path: "importer-\(UUID())")

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func makeImporter() -> PhotoImporter {
        PhotoImporter(importsDirectory: root.appending(path: "imports-\(UUID())"))
    }

    func pickedFile(named name: String, bytes: Data) throws -> URL {
        let folder = root.appending(path: "picked-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appending(path: name)
        try bytes.write(to: url)
        return url
    }

    func copies(in importer: PhotoImporter) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: importer.importsDirectory.path(percentEncoded: false))
    }

    @Test
    func aPickedFileIsCopiedUnderItsHashAndExcludedFromBackup() throws {
        let importer = makeImporter()
        let source   = try pickedFile(named: "DSC0001.ARW", bytes: Data([1, 2, 3]))

        let copy = try importer.importCopy(of: source)

        // SHA-256 of the bytes 01 02 03.
        let hash = "039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81"
        let backup = try importer.importsDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey])

        #expect(copy.isNew)
        #expect(copy.url.lastPathComponent == "\(hash)-DSC0001.ARW")
        #expect(try Data(contentsOf: copy.url) == Data([1, 2, 3]))
        #expect(backup.isExcludedFromBackup == true)
    }

    @Test
    func reopeningTheSameFileTwiceLeavesOneCopy() throws {
        let importer = makeImporter()
        let source   = try pickedFile(named: "DSC0001.ARW", bytes: Data([1, 2, 3]))

        let first  = try importer.importCopy(of: source)
        let second = try importer.importCopy(of: source)

        #expect(second.url == first.url)
        #expect(second.isNew == false)
        #expect(try copies(in: importer).count == 1)
    }

    @Test
    func aNewCopyOfAnOldFileIsDatedNow() throws {
        let importer = makeImporter()
        let source   = try pickedFile(named: "DSC0001.ARW", bytes: Data([1, 2, 3]))
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-86_400)],
            ofItemAtPath: source.path
        )

        let copy     = try importer.importCopy(of: source)
        let modified = try copy.url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate

        #expect(try #require(modified) > Date.now.addingTimeInterval(-60))
    }

    @Test
    func reusingACopyRefreshesItsAgeSoTheSweepKeepsIt() throws {
        let importer = makeImporter()
        let source   = try pickedFile(named: "DSC0001.ARW", bytes: Data([1, 2, 3]))
        let first    = try importer.importCopy(of: source)

        let longAgo = Date.now.addingTimeInterval(-86_400)
        try FileManager.default.setAttributes(
            [.modificationDate: longAgo],
            ofItemAtPath: first.url.path
        )
        _ = try importer.importCopy(of: source)

        let modified = try first.url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate
        #expect(try #require(modified) > Date.now.addingTimeInterval(-60))
    }

    @Test
    func twoDifferentFilesWithTheSameNameGetTwoCopies() throws {
        let importer = makeImporter()
        let first    = try pickedFile(named: "DSC0001.ARW", bytes: Data([1, 2, 3]))
        let second   = try pickedFile(named: "DSC0001.ARW", bytes: Data([4, 5, 6]))

        let firstCopy  = try importer.importCopy(of: first)
        let secondCopy = try importer.importCopy(of: second)

        #expect(firstCopy.url != secondCopy.url)
        #expect(try Data(contentsOf: secondCopy.url) == Data([4, 5, 6]))
        #expect(try copies(in: importer).count == 2)
    }

    @Test
    func aMissingFileIsACopyFailure() {
        let missing = URL(filePath: "/nonexistent/\(UUID()).ARW")
        #expect(throws: PhotoImportError.self) {
            _ = try makeImporter().importCopy(of: missing)
        }
    }
}
