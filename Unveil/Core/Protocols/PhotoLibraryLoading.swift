//
//  PhotoLibraryLoading.swift
//  Unveil
//

import Foundation

/// PhotoLibraryLoading preserves a picker's temporary image file until the editor has imported
/// it. The caller owns the returned file and must discard it after the import, including failures.
nonisolated protocol PhotoLibraryLoading: Sendable {

    @MainActor
    func loadPhoto(from provider: NSItemProvider) async throws(PhotoLibraryError) -> URL

    func discardPhoto(at url: URL) async throws(PhotoLibraryError)
}
