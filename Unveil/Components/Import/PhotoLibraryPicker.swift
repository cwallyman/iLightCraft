//
//  PhotoLibraryPicker.swift
//  Unveil
//

import Photos
import PhotosUI
import SwiftUI

/// PhotoLibraryPicker embeds the system Photos picker inline, without its Cancel and Add chrome.
/// Keeping the item provider preserves the loader's preference for RAW and its owned staging
/// file, and the picker runs out of process, so no library permission is ever requested.
///
/// Continuous selection delivers a pick on tap. The shared library only adds asset identifiers
/// to the results (no access), which lets the adapter deselect the pick at once, so the same
/// photo can be picked again later with a single tap. `isInteractive` false stops it taking
/// touches (the home panel is collapsed or importing).
struct PhotoLibraryPicker: UIViewControllerRepresentable {

    let onSelection  : (NSItemProvider) -> Void
    let isInteractive: Bool

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter                           = .images
        configuration.selectionLimit                   = 1
        configuration.selection                        = .continuous
        configuration.preferredAssetRepresentationMode = .current
        configuration.disabledCapabilities             = [.selectionActions, .stagingArea]
        configuration.edgesWithoutContentMargins       = .all

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ picker: PHPickerViewController,
        context : Context
    ) {
        context.coordinator.onSelection      = onSelection
        picker.view.isUserInteractionEnabled = isInteractive
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        var onSelection: (NSItemProvider) -> Void

        init(onSelection: @escaping (NSItemProvider) -> Void) {
            self.onSelection = onSelection
        }

        func picker(
            _ picker                : PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            guard let result = results.first else { return }

            picker.deselectAssets(withIdentifiers: results.compactMap(\.assetIdentifier))
            onSelection(result.itemProvider)
        }
    }
}
