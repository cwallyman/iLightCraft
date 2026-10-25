//
//  PhotoLibraryError.swift
//  iLightCraft
//

/// PhotoLibraryError separates a photo that is gone or has no image from failures while copying
/// it out of the library, so the editor can report the failure without losing the current photo.
nonisolated enum PhotoLibraryError: Error, Equatable {

    case photoUnavailable
    case noImageRepresentation
    case fileOperationFailed(String)
    case externalChange
    case invalidAdjustment

    var message: String {
        switch self {
            case .photoUnavailable:
                return "The photo is no longer in the library."

            case .noImageRepresentation:
                return "The selected item does not contain a supported image."

            case .fileOperationFailed(let message):
                return "Could not load the photo: \(message)"
            case .externalChange:
                return "This item changed in Apple Photos. Your local edit is retained; the Photos item was not overwritten."
            case .invalidAdjustment:
                return "This Photos edit needs a different version of iLightCraft. Your original and local edits are retained."
        }
    }
}
