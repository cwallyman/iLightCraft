//
//  PhotoLibraryLoaderTests.swift
//  iLightCraftTests
//

import Foundation
import Photos
import Testing
import UniformTypeIdentifiers
@testable import iLightCraft

@MainActor
struct PhotoLibraryLoaderTests {

    /// aRAWPairOpensItsRAW catches a choice that takes the JPEG of a RAW+JPEG pair, which Photos
    /// keeps as the photo while the RAW is only the alternate.
    @Test
    func aRAWPairOpensItsRAW() {
        let kinds = [
            kind(.photo, .jpeg),
            kind(.alternatePhoto, "com.fuji.raw-image")
        ]

        #expect(PhotoResourceChoice.preferredIndex(in: kinds) == 1)
        #expect(PhotoResourceChoice.isRAW(kinds))
    }

    /// aProRAWOpensItsOriginal catches a choice that skips a ProRAW: its DNG is the photo itself.
    @Test
    func aProRAWOpensItsOriginal() {
        let kinds = [
            kind(.photo, "com.adobe.raw-image"),
            kind(.fullSizePhoto, .jpeg)
        ]

        #expect(PhotoResourceChoice.preferredIndex(in: kinds) == 0)
        #expect(PhotoResourceChoice.isRAW(kinds))
    }

    /// anEditedPhotoOpensItsUneditedOriginal catches a choice that starts the editor from another
    /// app's render instead of the camera's pixels.
    @Test
    func anEditedPhotoOpensItsUneditedOriginal() {
        let kinds = [
            kind(.fullSizePhoto, .jpeg),
            kind(.photo, .heic),
            kind(.adjustmentData, "com.apple.photo.adjustment")
        ]

        #expect(PhotoResourceChoice.preferredIndex(in: kinds) == 1)
        #expect(!PhotoResourceChoice.isRAW(kinds))
    }

    /// onlyTheRenderIsStillOpenable and nothingStillIsRejected cover the fallbacks: a render when
    /// it is the only still image, nothing at all for a video.
    @Test
    func onlyTheRenderIsStillOpenable() {
        #expect(PhotoResourceChoice.preferredIndex(in: [kind(.fullSizePhoto, .jpeg)]) == 0)
    }

    @Test
    func nothingStillIsRejected() {
        #expect(PhotoResourceChoice.preferredIndex(in: [kind(.video, .quickTimeMovie)]) == nil)
    }

    /// theBadgeNamesTheFormat catches a badge that says "RAW" for every RAW format, shows a
    /// lowercase or empty name, or one format under two names (JPG and JPEG).
    @Test
    func theBadgeNamesTheFormat() {
        #expect(PhotoResourceChoice.formatName(fileName: "DSCF0267.raf", typeIdentifier: "com.fuji.raw-image") == "RAF")
        #expect(PhotoResourceChoice.formatName(fileName: "IMG_1361.DNG", typeIdentifier: "com.adobe.raw-image") == "DNG")
        #expect(PhotoResourceChoice.formatName(fileName: "photo", typeIdentifier: "com.adobe.raw-image") == "DNG")
        #expect(PhotoResourceChoice.formatName(fileName: "IMG_0042.jpg", typeIdentifier: "public.jpeg") == "JPEG")
        #expect(PhotoResourceChoice.formatName(fileName: "IMG_0042.HEIC", typeIdentifier: "public.heic") == "HEIC")
        #expect(PhotoResourceChoice.formatName(fileName: "photo", typeIdentifier: "public.png") == "PNG")
        #expect(PhotoResourceChoice.formatName(fileName: "photo", typeIdentifier: "not.a.type") == nil)
    }

    /// aVanishedPhotoIsReported catches a loader that fails with a file error, or crashes, when
    /// the photo was deleted between the tap and the load.
    @Test
    func aVanishedPhotoIsReported() async {
        let loader = PhotoLibraryLoader()

        await #expect(throws: PhotoLibraryError.photoUnavailable) {
            try await loader.loadPhoto(assetIdentifier: "no-such-asset/L0/001")
        }
    }

    /// discardRemovesTheWholeSelection catches a discard that leaves the selection's private
    /// directory behind, one per photo ever opened.
    @Test
    func discardRemovesTheWholeSelection() async throws {
        let staging   = URL.temporaryDirectory.appending(path: UUID().uuidString)
        let selection = staging.appending(path: UUID().uuidString)
        let staged    = selection.appending(path: "IMG_0001.DNG")
        try FileManager.default.createDirectory(at: selection, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: staged)
        defer { try? FileManager.default.removeItem(at: staging) }

        try await PhotoLibraryLoader(stagingDirectory: staging).discardPhoto(at: staged)

        #expect(!FileManager.default.fileExists(atPath: selection.path))
    }

    private func kind(_ type: PHAssetResourceType, _ contentType: UTType) -> PhotoResourceChoice.Kind {
        PhotoResourceChoice.Kind(type: type, typeIdentifier: contentType.identifier)
    }

    private func kind(_ type: PHAssetResourceType, _ typeIdentifier: String) -> PhotoResourceChoice.Kind {
        PhotoResourceChoice.Kind(type: type, typeIdentifier: typeIdentifier)
    }
}
