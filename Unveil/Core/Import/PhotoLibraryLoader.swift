//
//  PhotoLibraryLoader.swift
//  Unveil
//

import Foundation
import os
import UniformTypeIdentifiers

/// PhotoLibraryLoader asks Photos for a file representation instead of decoding a UIImage or
/// loading a whole RAW into Data. The provider deletes its file when the callback returns, so
/// the callback first preserves a copy; the editor's regular importer then owns the lasting copy.
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

    /// loadPhoto prefers a RAW representation when the provider exposes one. The continuation
    /// returns only after the callback has copied the file, keeping its lifetime explicit.
    /// Each selection gets its own directory but retains the filename, so importing the same
    /// photo again reaches the importer's existing content hash and does not create another copy.
    @MainActor
    func loadPhoto(from provider: NSItemProvider) async throws(PhotoLibraryError) -> URL {
        let imageTypes = provider.registeredTypeIdentifiers.compactMap { UTType($0) }
            .filter { $0.conforms(to: .image) }

        let preferredType = imageTypes.first { $0.conforms(to: .rawImage) } ?? imageTypes.first
        guard let imageType = preferredType else {
            throw .noImageRepresentation
        }

        let selectionDirectory = stagingDirectory.appending(
            path          : UUID().uuidString,
            directoryHint : .isDirectory
        )
        let result: Result<URL, PhotoLibraryError> = await withCheckedContinuation { continuation in
            provider.loadFileRepresentation(
                forTypeIdentifier: imageType.identifier
            ) { sourceURL, error in
                if let error {
                    continuation.resume(
                        returning: .failure(.fileOperationFailed(error.localizedDescription))
                    )
                    return
                }

                guard let sourceURL else {
                    continuation.resume(returning: .failure(.noImageRepresentation))
                    return
                }

                do {
                    let fileManager = FileManager.default
                    try fileManager.createDirectory(
                        at                          : selectionDirectory,
                        withIntermediateDirectories : true
                    )

                    let fileName = sourceURL.pathExtension.isEmpty
                        ? "photo.\(imageType.preferredFilenameExtension ?? "image")"
                        : sourceURL.lastPathComponent
                    let destination = selectionDirectory.appending(path: fileName)
                    try fileManager.copyItem(at: sourceURL, to: destination)

                    continuation.resume(returning: .success(destination))
                } catch {
                    if FileManager.default.fileExists(atPath: selectionDirectory.path) {
                        do {
                            try FileManager.default.removeItem(at: selectionDirectory)
                        } catch {
                            let logger = Logger(
                                subsystem : "com.eliorodr2104.unveil",
                                category  : "PhotoLibrary"
                            )
                            let message = error.localizedDescription
                            logger.error(
                                "Deleting a failed picker copy failed: \(message, privacy: .public)"
                            )
                        }
                    }

                    continuation.resume(
                        returning: .failure(.fileOperationFailed(error.localizedDescription))
                    )
                }
            }
        }

        return try result.get()
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
}
