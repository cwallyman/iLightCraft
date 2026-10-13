//
//  PhotoLibraryLoading.swift
//  Unveil
//

import Foundation

/// PhotoLibraryLoading copies a library photo, named by its asset identifier, into a staging file
/// the editor can import. The caller owns the returned file and must discard it after the import,
/// including failures.
nonisolated protocol PhotoLibraryLoading: Sendable {

    @MainActor
    func loadPhoto(assetIdentifier: String) async throws(PhotoLibraryError) -> URL

    func discardPhoto(at url: URL) async throws(PhotoLibraryError)
}
