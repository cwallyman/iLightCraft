//
//  PhotoLibraryPicker.swift
//  Unveil
//

import PhotosUI
import SwiftUI

/// PhotoLibraryPicker is the system picker adapter. Keeping the item provider preserves the
/// loader's preference for RAW and its owned staging file, without requesting library access.
struct PhotoLibraryPicker: UIViewControllerRepresentable {

    let onSelection: (NSItemProvider?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter                           = .images
        configuration.selectionLimit                   = 1
        configuration.preferredAssetRepresentationMode = .current

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ picker: PHPickerViewController,
        context : Context
    ) {
        context.coordinator.onSelection = onSelection
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelection: onSelection)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {

        var onSelection: (NSItemProvider?) -> Void

        init(onSelection: @escaping (NSItemProvider?) -> Void) {
            self.onSelection = onSelection
        }

        func picker(
            _ picker                : PHPickerViewController,
            didFinishPicking results: [PHPickerResult]
        ) {
            onSelection(results.first?.itemProvider)
        }
    }
}
