//
//  PhotoLibraryLoader.swift
//  Unveil
//

import Foundation
import os
import Photos
import UniformTypeIdentifiers

/// PhotoLibraryLoader opens a versioned Photos editing source, downloading from iCloud when needed.
/// Durable sources retain the PhotoKit revision and complete adjustment payload for same-item saves.
nonisolated struct PhotoLibraryLoader: PhotoLibraryLoading {

    private let stagingDirectory: URL

    init(
        stagingDirectory: URL = URL.temporaryDirectory.appending(
            path          : "UnveilPhotoSelections",
            directoryHint : .isDirectory
        )
    ) {
        self.stagingDirectory = stagingDirectory
    }

    /// loadPhoto delegates content editing to PhotoKit; RAW originals go through Apple's native decoder.
    @MainActor
    func loadPhoto(assetIdentifier: String) async throws(PhotoLibraryError) -> URL {
        do {
            return try await ApplePhotosEditor.prepare(identifier: assetIdentifier)
        } catch let error as PhotoLibraryError {
            throw error
        } catch {
            throw .fileOperationFailed(error.localizedDescription)
        }
    }

    /// Durable editing sources stay on device. Legacy temporary selections are discarded off the main actor.
    @concurrent
    func discardPhoto(at url: URL) async throws(PhotoLibraryError) {
        if FileManager.default.fileExists(atPath: url.appendingPathExtension("photos.json").path) { return }
        do {
            try FileManager.default.removeItem(at: url.deletingLastPathComponent())
        } catch {
            throw .fileOperationFailed(error.localizedDescription)
        }
    }

    /// removeQuietly deletes a failed selection's directory; a failure there is only logged,
    /// because the load's own error is the one the user needs.
    private static func removeQuietly(_ directory: URL) {
        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            let logger = Logger(subsystem: "com.eliorodr2104.unveil", category: "PhotoLibrary")
            logger.error("Deleting a failed library copy failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

/// PhotoResourceChoice picks which of an asset's resources the editor opens. A RAW editor wants
/// the RAW: a RAW+JPEG pair keeps it as the alternate photo, a ProRAW keeps it as the photo
/// itself. Without a RAW it takes the unedited original, and only then the edited render, so
/// the editor starts from the camera's pixels rather than from another app's adjustments.
nonisolated enum PhotoResourceChoice {

    /// Kind is the part of a resource the choice looks at.
    struct Kind: Equatable {

        let type          : PHAssetResourceType
        let typeIdentifier: String

        var isRAW: Bool {
            UTType(typeIdentifier)?.conforms(to: .rawImage) ?? false
        }
    }

    /// preferredIndex is the index of the resource to open, or nil when none is a still image.
    static func preferredIndex(in kinds: [Kind]) -> Int? {
        let originals: [PHAssetResourceType] = [.photo, .alternatePhoto]

        if let raw = kinds.firstIndex(where: { originals.contains($0.type) && $0.isRAW }) {
            return raw
        }
        if let original = kinds.firstIndex(where: { $0.type == .photo }) {
            return original
        }
        return kinds.firstIndex { $0.type == .fullSizePhoto }
    }

    /// isRAW tells whether the asset has a RAW to open.
    static func isRAW(_ kinds: [Kind]) -> Bool {
        preferredIndex(in: kinds).map { kinds[$0].isRAW } ?? false
    }

    /// formatName is a photo's format as the grid's badge shows it: the file's own extension in
    /// capitals (JPEG, HEIC, PNG, DNG, RAF, NEF, CR3...), else the type's usual extension, with
    /// JPG spelled JPEG so one format never shows under two names. A RAW whose type is unknown is
    /// "RAW"; any other unknown file has no badge.
    static func formatName(fileName: String, typeIdentifier: String) -> String? {
        let type          = UTType(typeIdentifier)
        let fileExtension = (fileName as NSString).pathExtension

        guard let name = fileExtension.isEmpty ? type?.preferredFilenameExtension : fileExtension else {
            return type?.conforms(to: .rawImage) == true ? "RAW" : nil
        }

        switch name.uppercased() {
            case "JPG", "JPE":
                return "JPEG"

            case let upper:
                return upper
        }
    }
}
