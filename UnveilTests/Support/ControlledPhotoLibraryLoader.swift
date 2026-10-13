//
//  ControlledPhotoLibraryLoader.swift
//  UnveilTests
//

import Foundation
@testable import Unveil

/// ControlledPhotoLibraryLoader pauses a selection so tests can attempt another import while
/// the first one still owns its staging file.
@MainActor
final class ControlledPhotoLibraryLoader: PhotoLibraryLoading {

    private(set) var loadCount    : Int = 0
    private(set) var discardedURLs: [URL] = []

    private var continuation: CheckedContinuation<Result<URL, PhotoLibraryError>, Never>?

    func loadPhoto(assetIdentifier: String) async throws(PhotoLibraryError) -> URL {
        loadCount += 1
        let result = await withCheckedContinuation { continuation = $0 }
        return try result.get()
    }

    nonisolated func discardPhoto(at url: URL) async throws(PhotoLibraryError) {
        await recordDiscard(url)
    }

    func complete(_ result: Result<URL, PhotoLibraryError>) {
        continuation?.resume(returning: result)
        continuation = nil
    }

    private func recordDiscard(_ url: URL) {
        discardedURLs.append(url)
    }
}
