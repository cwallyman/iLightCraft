//
//  PhotoLibraryLoaderTests.swift
//  UnveilTests
//

import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Unveil

@MainActor
struct PhotoLibraryLoaderTests {

    /// preservedFileOutlivesTheProvider catches a loader that returns the provider's borrowed
    /// URL, or discards the app's imported file together with the temporary selection.
    @Test
    func preservedFileOutlivesTheProvider() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeFixtures(at: directory) }

        let bytes     = Data([1, 2, 3, 4])
        let sourceURL = directory.appending(path: "photo.png")
        try bytes.write(to: sourceURL)

        let provider  = try #require(NSItemProvider(contentsOf: sourceURL))
        let loader    = PhotoLibraryLoader(stagingDirectory: directory.appending(path: "Staging"))
        let pickedURL = try await loader.loadPhoto(from: provider)
        try FileManager.default.removeItem(at: sourceURL)

        #expect(try Data(contentsOf: pickedURL) == bytes)
        #expect(pickedURL.pathExtension == "png")

        let importer = PhotoImporter(importsDirectory: directory.appending(path: "Imports"))
        let imported = try importer.importCopy(of: pickedURL)
        try await loader.discardPhoto(at: pickedURL)

        #expect(!FileManager.default.fileExists(atPath: pickedURL.path))
        #expect(try Data(contentsOf: imported.url) == bytes)
    }

    /// rawRepresentationIsPreserved catches a picker adapter that takes a JPEG preview when
    /// the provider also offers the RAW that the editor can develop itself.
    @Test
    func rawRepresentationIsPreserved() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeFixtures(at: directory) }

        let jpegURL = directory.appending(path: "preview.jpg")
        let rawURL  = directory.appending(path: "original.RAF")
        try Data([1]).write(to: jpegURL)
        try Data([7, 8, 9]).write(to: rawURL)

        let provider = NSItemProvider()
        provider.registerFileRepresentation(
            forTypeIdentifier : UTType.jpeg.identifier,
            fileOptions       : [],
            visibility        : .all
        ) { completion in
            completion(jpegURL, false, nil)
            return nil
        }
        provider.registerFileRepresentation(
            forTypeIdentifier : UTType.rawImage.identifier,
            fileOptions       : [],
            visibility        : .all
        ) { completion in
            completion(rawURL, false, nil)
            return nil
        }

        let loader    = PhotoLibraryLoader(stagingDirectory: directory.appending(path: "Staging"))
        let pickedURL = try await loader.loadPhoto(from: provider)

        #expect(try Data(contentsOf: pickedURL) == Data([7, 8, 9]))
        #expect(pickedURL.pathExtension == "RAF")
    }

    /// nonImageSelectionIsRejected catches a loader that sends an unrelated representation
    /// into the photo importer instead of reporting the selection error.
    @Test
    func nonImageSelectionIsRejected() async throws {
        let provider = NSItemProvider(object: NSString(string: "text"))
        let loader   = PhotoLibraryLoader()

        await #expect(throws: PhotoLibraryError.noImageRepresentation) {
            try await loader.loadPhoto(from: provider)
        }
    }

    /// repeatedSelectionsReuseTheImportedCopy catches staging names that defeat the importer's
    /// content-based identity and create another permanent RAW every time Photos is opened.
    @Test
    func repeatedSelectionsReuseTheImportedCopy() async throws {
        let directory = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { removeFixtures(at: directory) }

        let sourceURL = directory.appending(path: "photo.png")
        try Data([1, 2, 3, 4]).write(to: sourceURL)

        let provider = try #require(NSItemProvider(contentsOf: sourceURL))
        let loader   = PhotoLibraryLoader(stagingDirectory: directory.appending(path: "Staging"))
        let importer = PhotoImporter(importsDirectory: directory.appending(path: "Imports"))

        let firstSelection = try await loader.loadPhoto(from: provider)
        let firstImport    = try importer.importCopy(of: firstSelection)
        try await loader.discardPhoto(at: firstSelection)

        let secondSelection = try await loader.loadPhoto(from: provider)
        let secondImport    = try importer.importCopy(of: secondSelection)
        try await loader.discardPhoto(at: secondSelection)

        #expect(firstImport.isNew)
        #expect(!secondImport.isNew)
        #expect(firstImport.url == secondImport.url)
        #expect(
            !FileManager.default.fileExists(atPath: secondSelection.deletingLastPathComponent().path)
        )
    }

    /// removeFixtures reports cleanup failures so a test never silently leaves temporary photos.
    private func removeFixtures(at directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record(error)
        }
    }
}
