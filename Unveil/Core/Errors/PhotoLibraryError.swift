//
//  PhotoLibraryError.swift
//  Unveil
//

/// PhotoLibraryError separates an unavailable image from failures while loading or preserving
/// the picker file, so the editor can report the failure without losing the current photo.
nonisolated enum PhotoLibraryError: Error, Equatable {

    case noImageRepresentation
    case fileOperationFailed(String)

    var message: String {
        switch self {
            case .noImageRepresentation:
                return "The selected item does not contain a supported image."

            case .fileOperationFailed(let message):
                return "Could not load the photo: \(message)"
        }
    }
}
