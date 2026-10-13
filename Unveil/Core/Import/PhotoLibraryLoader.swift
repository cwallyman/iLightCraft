//
//  PhotoLibraryLoader.swift
//  Unveil
//

import Foundation
import os
import Photos
import UniformTypeIdentifiers

/// PhotoLibraryLoader copies one library photo out of Photos as a file, never as a decoded
/// UIImage and never whole into Data: Photos writes the chosen resource straight to a staging
/// file, downloading it from iCloud when needed. The editor's regular importer then owns the
/// lasting copy, and the caller discards the staging file.
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

    /// loadPhoto writes the asset's best resource (PhotoResourceChoice: the RAW when there is
    /// one) into a directory of its own under its original file name, so importing the same photo
    /// again reaches the importer's existing content hash and does not create another copy.
    @MainActor
    func loadPhoto(assetIdentifier: String) async throws(PhotoLibraryError) -> URL {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [assetIdentifier], options: nil).firstObject else {
            throw .photoUnavailable
        }

        let resources = PHAssetResource.assetResources(for: asset)
        let kinds     = resources.map { PhotoResourceChoice.Kind(type: $0.type, typeIdentifier: $0.uniformTypeIdentifier) }
        guard let index = PhotoResourceChoice.preferredIndex(in: kinds) else {
            throw .noImageRepresentation
        }

        let resource           = resources[index]
        let selectionDirectory = stagingDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let fileName           = resource.originalFilename.isEmpty
            ? "photo.\(UTType(resource.uniformTypeIdentifier)?.preferredFilenameExtension ?? "image")"
            : resource.originalFilename
        let destination = selectionDirectory.appending(path: fileName)

        do {
            try FileManager.default.createDirectory(at: selectionDirectory, withIntermediateDirectories: true)
        } catch {
            throw .fileOperationFailed(error.localizedDescription)
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let failure: String? = await withCheckedContinuation { continuation in
            PHAssetResourceManager.default().writeData(for: resource, toFile: destination, options: options) { error in
                continuation.resume(returning: error?.localizedDescription)
            }
        }

        if let failure {
            Self.removeQuietly(selectionDirectory)
            throw .fileOperationFailed(failure)
        }

        return destination
    }

    /// discardPhoto removes the selection's private directory off the main actor, including any
    /// staged file. Its URL must be one returned by loadPhoto; the lasting import lives elsewhere.
    @concurrent
    func discardPhoto(at url: URL) async throws(PhotoLibraryError) {
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
