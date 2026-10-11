//
//  PhotoImportActions.swift
//  Unveil
//

import SwiftUI

/// PhotoImportActions keeps the toolbar and empty-state menus on the same two import paths.
struct PhotoImportActions: View {

    let openPhotos: () -> Void
    let openFiles : () -> Void

    var body: some View {
        Button(
            "Photos",
            systemImage : "photo",
            action      : openPhotos
        )

        Button(
            "Files",
            systemImage : "folder",
            action      : openFiles
        )
    }
}
